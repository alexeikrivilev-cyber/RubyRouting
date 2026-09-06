# frozen_string_literal: true

require_relative "../test_helper"

class WorkingStateRestorerTest < Minitest::Test
  Fact = Struct.new(:sequence)

  def test_replays_in_sequence_order_and_validates_supplied_catalog_after_replay
    events = []
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "provider")
    catalog = nil
    restorer = RubyRouting::State::WorkingStateRestorer.new(
      prepare_catalog: -> {
        events << :prepare
        catalog = RubyRouting::State::ProviderCatalogLedger.new
      },
      current_catalog: -> { catalog },
      restore_fact: ->(fact) {
        events << [:restore, fact.sequence]
        catalog.register(provider, sequence: fact.sequence) if fact.sequence == 1
      },
      validate_state: -> { events << :validate }
    )

    assert_nil restorer.restore!(facts: [Fact.new(2), Fact.new(1)], opportunities: [provider])
    assert_equal [:prepare, [:restore, 1], [:restore, 2], :validate], events
    assert_equal ["provider"], catalog.provider_ids
  end

  def test_wraps_reducer_shape_failures_at_the_durable_corruption_boundary
    validated = false
    restorer = RubyRouting::State::WorkingStateRestorer.new(
      prepare_catalog: -> {},
      current_catalog: -> { RubyRouting::State::ProviderCatalogLedger.new },
      restore_fact: ->(_fact) { raise ArgumentError, "bad reducer payload" },
      validate_state: -> { validated = true }
    )

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      restorer.restore!(facts: [Fact.new(7)], opportunities: [])
    end

    assert_match(/fact 7 cannot restore working state: bad reducer payload/, error.message)
    refute validated
  end

  def test_preserves_existing_durable_corruption_errors
    expected = RubyRouting::State::DurableCorruptionError.new("already classified")
    restorer = RubyRouting::State::WorkingStateRestorer.new(
      prepare_catalog: -> {},
      current_catalog: -> { RubyRouting::State::ProviderCatalogLedger.new },
      restore_fact: ->(_fact) { raise expected },
      validate_state: -> {}
    )

    error = assert_raises(RubyRouting::State::DurableCorruptionError) do
      restorer.restore!(facts: [Fact.new(3)], opportunities: [])
    end

    assert_same expected, error
  end

  def test_rejects_supplied_provider_missing_from_durable_current_catalog
    provider = RubyRouting::ProviderOpportunity.new(provider_id: "not-restored")
    validated = false
    restorer = RubyRouting::State::WorkingStateRestorer.new(
      prepare_catalog: -> {},
      current_catalog: -> { RubyRouting::State::ProviderCatalogLedger.new },
      restore_fact: ->(_fact) {},
      validate_state: -> { validated = true }
    )

    error = assert_raises(ArgumentError) do
      restorer.restore!(facts: [Fact.new(1)], opportunities: [provider])
    end

    assert_match(/supplied opportunity not-restored is not current in durable provider history/, error.message)
    refute validated
  end
end
