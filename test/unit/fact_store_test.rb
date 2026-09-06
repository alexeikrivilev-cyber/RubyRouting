# frozen_string_literal: true

require_relative "../test_helper"

class FactStoreTest < Minitest::Test
  def test_constructor_rejects_non_enumerable_fact_input
    assert_raises(ArgumentError) do
      RubyRouting::State::FactStore.new(facts: Object.new)
    end
  end

  def test_constructor_accepts_an_each_only_enumerable
    fact = RubyRouting::Fact.new(
      sequence: 1,
      type: :intent_registered,
      fact_id: "fact:1",
      payout_id: "payout-1"
    )

    store = RubyRouting::State::FactStore.new(
      facts: TestSupport::EachOnlyCollection.new([fact])
    )

    assert_equal [fact], store.facts
  end

  def test_indexed_audit_queries_and_pages_preserve_fact_order
    store = RubyRouting::State::FactStore.new
    first = store.append(type: :intent_registered, payout_id: "payout-1")
    second = store.append(type: :provider_observed, payout_id: "payout-2")
    third = store.append(type: :provider_observed, payout_id: "payout-1")
    fourth = store.append(type: :settlement_recorded, payout_id: "payout-1")

    assert_equal [first, third, fourth], store.query(payout_id: "payout-1")
    assert_equal [second, third], store.query(type: :provider_observed)
    assert_equal [third], store.query(payout_id: "payout-1", type: :provider_observed)

    page = store.page(payout_id: "payout-1", offset: 1, limit: 1)
    assert_equal [third], page.facts
    assert_equal 1, page.offset
    assert_equal 1, page.limit
    assert_equal 3, page.total
    assert_equal 2, page.next_offset
    assert_predicate page.facts, :frozen?
  end

  def test_indexed_query_includes_staged_transaction_facts
    store = RubyRouting::State::FactStore.new
    committed = store.append(type: :intent_registered, payout_id: "payout-1")

    store.transaction do
      staged = store.append(type: :settlement_recorded, payout_id: "payout-1")

      assert_equal [committed, staged], store.query(payout_id: "payout-1")
      assert_equal [staged], store.page(
        payout_id: "payout-1",
        type: :settlement_recorded,
        offset: 0,
        limit: 1
      ).facts
    end
  end

  def test_fact_page_rejects_non_integer_or_invalid_bounds
    store = RubyRouting::State::FactStore.new

    assert_raises(ArgumentError) { store.page(offset: -1, limit: 1) }
    assert_raises(ArgumentError) { store.page(offset: 0, limit: 0) }
    assert_raises(ArgumentError) { store.page(offset: 0, limit: 1.0) }
  end

  Journal = Struct.new(:facts) do
    def initialize
      super([])
    end

    def append(fact)
      facts << fact
    end
  end

  class FailBeforeAppendJournal
    attr_reader :facts

    def initialize
      @facts = []
      @fail = false
    end

    def fail_next!
      @fail = true
    end

    def append_many(facts)
      if @fail
        @fail = false
        raise IOError, "injected durable append failure"
      end

      @facts.concat(facts)
    end
  end

  class FailAfterAppendJournal
    attr_reader :facts

    def initialize
      @facts = []
      @fail = false
    end

    def fail_next!
      @fail = true
    end

    def append_many(facts)
      @facts.concat(facts)
      if @fail
        @fail = false
        raise IOError, "injected post-append durable failure"
      end
    end
  end

  class PartialAppendJournal
    def initialize
      @facts = []
      @poisoned = false
    end

    def facts
      raise RubyRouting::State::DurableCorruptionError, "journal is poisoned" if @poisoned

      @facts
    end

    def append_many(new_facts)
      raise RubyRouting::State::DurableCorruptionError, "journal is poisoned" if @poisoned

      @facts << new_facts.first
      raise IOError, "injected partial durable append failure"
    end

    def poison!(_reason)
      @poisoned = true
    end

    def poisoned?
      @poisoned
    end
  end

  class OpaquePartialAppendJournal
    attr_reader :stored_facts, :append_count

    def initialize
      @stored_facts = []
      @append_count = 0
    end

    def append_many(new_facts)
      @append_count += 1
      @stored_facts << new_facts.first
      raise IOError, "injected opaque partial durable append failure"
    end
  end

  class OpaquePoisonFailureJournal
    attr_reader :append_count

    def initialize
      @append_count = 0
    end

    def append_many(_new_facts)
      @append_count += 1
      raise IOError, "injected opaque append failure"
    end

    def poison!(_reason)
      raise IOError, "injected poison failure"
    end
  end

  def test_append_assigns_monotonic_identity_and_revision
    store = RubyRouting::State::FactStore.new

    first = store.append(type: :intent_registered, payout_id: "payout-1", payload: {value: 1})
    second = store.append(type: :payout_state_changed, payout_id: "payout-1")

    assert_equal 1, first.sequence
    assert_equal "fact:1", first.fact_id
    assert_equal 2, second.sequence
    assert_equal "fact:2", second.fact_id
    assert_equal 2, store.revision
    assert_equal [first, second], store.facts
  end

  def test_durable_store_reports_when_it_has_a_journal
    refute RubyRouting::State::FactStore.new.durable?
    assert RubyRouting::State::FactStore.new(journal: Journal.new).durable?
  end

  def test_explicit_memory_facts_must_match_the_durable_journal
    journal = Journal.new
    store = RubyRouting::State::FactStore.new(journal: journal)
    stored = store.append(type: :intent_registered, payout_id: "payout-1")
    mismatched = RubyRouting::Fact.new(
      sequence: stored.sequence,
      type: stored.type,
      fact_id: stored.fact_id,
      payout_id: stored.payout_id,
      payload: { different: true }
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::FactStore.new(journal: journal, facts: [mismatched])
    end
  end

  def test_facts_are_snapshot_safe_and_payloads_remain_immutable
    store = RubyRouting::State::FactStore.new
    store.append(type: :intent_registered, payout_id: "payout-1", payload: {nested: ["value"]})

    facts = store.facts

    assert_predicate facts, :frozen?
    assert_raises(FrozenError) { facts << :unexpected }
    assert_predicate facts.first.payload, :frozen?
    assert_predicate facts.first.payload.fetch(:nested), :frozen?
  end

  def test_journal_receives_the_same_facts_in_append_order
    journal = Journal.new
    store = RubyRouting::State::FactStore.new(journal: journal)

    first = store.append(type: :intent_registered, payout_id: "payout-1")
    second = store.append(type: :payout_state_changed, payout_id: "payout-1")

    assert_equal [first, second], journal.facts
  end

  def test_failed_durable_append_does_not_advance_store
    journal = FailBeforeAppendJournal.new
    store = RubyRouting::State::FactStore.new(journal: journal)
    journal.fail_next!

    assert_raises(IOError) do
      store.append(type: :intent_registered, payout_id: "payout-1")
    end

    assert_empty store.facts
    assert_equal 0, store.revision
    assert_empty journal.facts
    first = store.append(type: :intent_registered, payout_id: "payout-1")
    assert_equal 1, first.sequence
  end

  def test_transaction_publishes_a_fact_batch_only_after_journal_accepts_it
    journal = FailBeforeAppendJournal.new
    store = RubyRouting::State::FactStore.new(journal: journal)
    journal.fail_next!

    assert_raises(IOError) do
      store.transaction do
        store.append(type: :intent_registered, payout_id: "payout-1")
        store.append(type: :payout_state_changed, payout_id: "payout-1")
      end
    end

    assert_empty store.facts
    assert_equal 0, store.revision
    assert_empty journal.facts
    store.transaction do
      store.append(type: :intent_registered, payout_id: "payout-1")
      store.append(type: :payout_state_changed, payout_id: "payout-1")
    end
    assert_equal [1, 2], store.facts.map(&:sequence)
    assert_equal store.facts, journal.facts
  end

  def test_post_append_failure_is_reconciled_when_the_complete_batch_is_visible
    journal = FailAfterAppendJournal.new
    store = RubyRouting::State::FactStore.new(journal: journal)
    journal.fail_next!

    store.transaction do
      store.append(type: :intent_registered, payout_id: "payout-1")
      store.append(type: :payout_state_changed, payout_id: "payout-1")
    end

    assert_equal [1, 2], store.facts.map(&:sequence)
    assert_equal store.facts.map(&:payload), journal.facts.map(&:payload)
    next_fact = store.append(type: :payout_state_changed, payout_id: "payout-1")
    assert_equal 3, next_fact.sequence
    assert_equal [1, 2, 3], journal.facts.map(&:sequence)
  end

  def test_partial_append_poisoning_prevents_continuing_with_a_non_prefix_journal
    journal = PartialAppendJournal.new
    store = RubyRouting::State::FactStore.new(journal: journal)

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      store.transaction do
        store.append(type: :intent_registered, payout_id: "payout-1")
        store.append(type: :payout_state_changed, payout_id: "payout-1")
      end
    end

    assert_empty store.facts
    assert journal.poisoned?
    assert_raises(RubyRouting::State::DurableCorruptionError) do
      store.append(type: :intent_registered, payout_id: "payout-1")
    end
  end

  def test_unobservable_append_failure_fails_closed_before_fact_identity_reuse
    journal = OpaquePartialAppendJournal.new
    store = RubyRouting::State::FactStore.new(journal: journal)

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      store.transaction do
        store.append(type: :intent_registered, payout_id: "payout-1")
        store.append(type: :payout_state_changed, payout_id: "payout-1")
      end
    end

    assert_includes error.message, "append outcome is unknown"
    assert_empty store.facts
    assert_equal 1, journal.append_count
    assert_equal ["fact:1"], journal.stored_facts.map(&:fact_id)
    assert_raises(RubyRouting::State::DurableCorruptionError) do
      store.append(type: :intent_registered, payout_id: "payout-1")
    end
    assert_equal 1, journal.append_count
  end

  def test_poison_hook_failure_does_not_mask_unobservable_append_corruption
    journal = OpaquePoisonFailureJournal.new
    store = RubyRouting::State::FactStore.new(journal: journal)

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      store.append(type: :intent_registered, payout_id: "payout-1")
    end

    assert_includes error.message, "append outcome is unknown"
    assert_equal 1, journal.append_count
    assert_raises(RubyRouting::State::DurableCorruptionError) do
      store.append(type: :intent_registered, payout_id: "payout-1")
    end
    assert_equal 1, journal.append_count
  end
end
