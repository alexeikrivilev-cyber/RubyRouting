# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class FactCodecTest < Minitest::Test
  def test_batch_boundaries_reject_non_enumerable_input
    assert_raises(ArgumentError) { RubyRouting::State::FactCodec.encode_batch(nil) }

    Dir.mktmpdir("ruby-routing-journal-input") do |directory|
      journal = RubyRouting::State::FileJournal.new(File.join(directory, "facts.jsonl"))
      assert_raises(ArgumentError) { journal.append_many(nil) }
    end
  end

  def test_batch_boundaries_accept_an_each_only_enumerable
    fact = RubyRouting::Fact.new(
      sequence: 1,
      type: :intent_registered,
      fact_id: "fact:1",
      payout_id: "each-only"
    )
    collection = TestSupport::EachOnlyCollection.new([fact])

    encoded = RubyRouting::State::FactCodec.encode_batch(collection)
    restored = RubyRouting::State::FactCodec.decode_batch(encoded).first
    assert_equal [fact.sequence, fact.type, fact.fact_id, fact.payout_id, fact.payload],
      [restored.sequence, restored.type, restored.fact_id, restored.payout_id, restored.payload]

    Dir.mktmpdir("ruby-routing-journal-each-only") do |directory|
      journal = RubyRouting::State::FileJournal.new(File.join(directory, "facts.jsonl"))
      journal.append_many(TestSupport::EachOnlyCollection.new([fact]))
      restored = journal.facts.first
      assert_equal [fact.sequence, fact.type, fact.fact_id, fact.payout_id, fact.payload],
        [restored.sequence, restored.type, restored.fact_id, restored.payout_id, restored.payload]
    end
  end

  def test_fact_materializes_each_only_nested_values_for_durable_encoding
    fact = RubyRouting::Fact.new(
      sequence: 1,
      type: :opportunity_evaluated,
      fact_id: "fact:each-only-nested",
      payout_id: "each-only-nested",
      payload: {
        labels: TestSupport::EachOnlyCollection.new(["retail", :priority])
      }
    )

    assert_equal ["retail", :priority], fact.payload.fetch(:labels)
    assert_predicate fact.payload.fetch(:labels), :frozen?

    restored = RubyRouting::State::FactCodec.decode_fact(
      RubyRouting::State::FactCodec.encode_fact(fact)
    )
    assert_equal fact.payload, restored.payload
  end

  def test_each_only_payout_context_is_materialized_for_durable_restore
    Dir.mktmpdir("ruby-routing-intent-context") do |directory|
      path = File.join(directory, "facts.jsonl")
      journal = RubyRouting::State::FileJournal.new(path)
      coordinator = RubyRouting::State::Coordinator.new(
        journal: journal,
        opportunities: [RubyRouting::ProviderOpportunity.new(provider_id: "A")]
      )
      policy = RubyRouting::RoutingPolicy.new(
        id: "each-only-intent-context",
        epoch: "1",
        measure: :count,
        targets: { "A" => 1 },
        hard_constraints: RubyRouting::RoutingConstraints.new(
          required_context_labels: ["retail"]
        )
      )
      intent = RubyRouting::PayoutIntent.new(
        id: "each-only-intent-context-payout",
        money: RubyRouting::Money.new(100, "RUB"),
        context: { labels: TestSupport::EachOnlyCollection.new(["retail"]) }
      )

      committed = coordinator.prepare_and_commit_decision(intent: intent, policy: policy)
      restored = RubyRouting::State::Coordinator.new(
        journal: RubyRouting::State::FileJournal.new(path)
      )

      assert_equal ["retail"], intent.context[:labels]
      assert_equal ["retail"], restored.payout_snapshot(intent.id).intent.context[:labels]
      assert_equal committed.proposal.operation_id,
        restored.payout_snapshot(intent.id).ownership.operation_id
    end
  end

  def test_round_trip_preserves_domain_values_and_nested_fact_payload
    fact = RubyRouting::Fact.new(
      sequence: 1,
      type: :opportunity_evaluated,
      fact_id: "fact:1",
      payout_id: "codec-payout",
      payload: {
        symbol: :primary,
        ratio: Rational(2, 3),
        timestamp: Time.utc(2026, 8, 28, 12, 34, 56, 123_456),
        money: RubyRouting::Money.new(125, "RUB"),
        nested: { providers: ["A", :B, { amount: 0 }] }
      }
    )

    restored = RubyRouting::State::FactCodec.decode_fact(
      RubyRouting::State::FactCodec.encode_fact(fact)
    )

    assert_equal fact.sequence, restored.sequence
    assert_equal fact.type, restored.type
    assert_equal fact.fact_id, restored.fact_id
    assert_equal fact.payout_id, restored.payout_id
    assert_equal fact.payload, restored.payload
  end

  def test_financial_codec_rejects_float_values
    fact = RubyRouting::Fact.new(
      sequence: 1,
      type: :intent_registered,
      fact_id: "fact:1",
      payout_id: "float-payout",
      payload: { ratio: 0.5 }
    )

    assert_raises(ArgumentError) { RubyRouting::State::FactCodec.encode_fact(fact) }
  end

  def test_financial_codec_rejects_float_values_when_decoding
    body = {
      "version" => RubyRouting::State::FactCodec::VERSION,
      "sequence" => 1,
      "type" => "intent_registered",
      "fact_id" => "fact:1",
      "payout_id" => "float-payout",
      "payload" => { "$type" => "array", "items" => [0.5] }
    }
    record = body.merge(
      "checksum" => Digest::SHA256.hexdigest(JSON.generate(body))
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::FactCodec.decode_fact(JSON.generate(record))
    end
  end

  def test_financial_codec_rejects_float_values_in_an_untagged_raw_array
    symbol = "uninterned-raw-array-float-#{Process.pid}-#{object_id}"
    body = {
      "version" => RubyRouting::State::FactCodec::VERSION,
      "sequence" => 1,
      "type" => "intent_registered",
      "fact_id" => "fact:raw-array-float",
      "payout_id" => "raw-array-float",
      "payload" => [0.5, symbol]
    }
    record = body.merge(
      "checksum" => Digest::SHA256.hexdigest(JSON.generate(body))
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::FactCodec.decode_fact(JSON.generate(record))
    end
  end

  def test_durable_unknown_symbol_is_not_interned
    symbol_name = "uninterned-durable-symbol-#{Process.pid}-#{object_id}"
    refute Symbol.all_symbols.any? { |symbol| symbol.to_s == symbol_name }
    body = {
      "version" => RubyRouting::State::FactCodec::VERSION,
      "sequence" => 1,
      "type" => "intent_registered",
      "fact_id" => "fact:unknown-symbol",
      "payout_id" => "unknown-symbol",
      "payload" => { "$type" => "symbol", "value" => symbol_name }
    }
    record = body.merge(
      "checksum" => Digest::SHA256.hexdigest(JSON.generate(body))
    )

    restored = RubyRouting::State::FactCodec.decode_fact(JSON.generate(record))

    assert_equal symbol_name, restored.payload
    refute Symbol.all_symbols.any? { |symbol| symbol.to_s == symbol_name }
  end

  def test_financial_codec_rejects_float_rational_components_when_decoding
    body = {
      "version" => RubyRouting::State::FactCodec::VERSION,
      "sequence" => 1,
      "type" => "intent_registered",
      "fact_id" => "fact:1",
      "payout_id" => "float-rational-payout",
      "payload" => {
        "$type" => "rational",
        "numerator" => 0.5,
        "denominator" => 1
      }
    }
    record = body.merge(
      "checksum" => Digest::SHA256.hexdigest(JSON.generate(body))
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::FactCodec.decode_fact(JSON.generate(record))
    end
  end

  def test_durable_codec_rejects_duplicate_hash_entries
    body = {
      "version" => RubyRouting::State::FactCodec::VERSION,
      "sequence" => 1,
      "type" => "intent_registered",
      "fact_id" => "fact:1",
      "payout_id" => "duplicate-hash-key",
      "payload" => {
        "$type" => "hash",
        "entries" => [
          ["status", { "$type" => "symbol", "value" => "pending" }],
          ["status", { "$type" => "symbol", "value" => "success" }]
        ]
      }
    }
    record = body.merge(
      "checksum" => Digest::SHA256.hexdigest(JSON.generate(body))
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::FactCodec.decode_fact(JSON.generate(record))
    end
  end

  def test_durable_codec_rejects_unknown_nested_and_envelope_fields
    body = {
      "version" => RubyRouting::State::FactCodec::VERSION,
      "sequence" => 1,
      "type" => "intent_registered",
      "fact_id" => "fact:extra-fields",
      "payout_id" => "extra-fields",
      "payload" => {
        "$type" => "array",
        "items" => [],
        "unsupported" => "must-not-be-dropped"
      },
      "unsupported" => "must-not-be-dropped"
    }
    record = body.merge(
      "checksum" => Digest::SHA256.hexdigest(JSON.generate(body))
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::FactCodec.decode_fact(JSON.generate(record))
    end
  end

  def test_durable_codec_rejects_noncanonical_fact_envelope_identity
    body = {
      "version" => RubyRouting::State::FactCodec::VERSION,
      "sequence" => 1,
      "type" => "intent_registered",
      "fact_id" => 1,
      "payout_id" => 123,
      "payload" => {}
    }
    record = body.merge(
      "checksum" => Digest::SHA256.hexdigest(JSON.generate(body))
    )

    assert_raises(RubyRouting::State::DurableCorruptionError) do
      RubyRouting::State::FactCodec.decode_fact(JSON.generate(record))
    end
  end

  def test_batch_codec_keeps_a_coordinator_mutation_as_one_durable_record
    facts = 2.times.map do |index|
      RubyRouting::Fact.new(
        sequence: index + 1,
        type: index.zero? ? :intent_registered : :payout_state_changed,
        fact_id: "fact:#{index + 1}",
        payout_id: "batch-payout",
        payload: { step: index + 1 }
      )
    end

    encoded = RubyRouting::State::FactCodec.encode_batch(facts)
    restored = RubyRouting::State::FactCodec.decode_batch(encoded)

    assert_equal facts.map { |fact| [fact.sequence, fact.type, fact.fact_id, fact.payload] },
      restored.map { |fact| [fact.sequence, fact.type, fact.fact_id, fact.payload] }
    assert_equal 2, restored.length
  end

  def test_file_journal_writes_one_line_for_a_fact_batch
    Dir.mktmpdir("ruby-routing-batch") do |directory|
      path = File.join(directory, "facts.jsonl")
      journal = RubyRouting::State::FileJournal.new(path)
      facts = 2.times.map do |index|
        RubyRouting::Fact.new(
          sequence: index + 1,
          type: :payout_state_changed,
          fact_id: "fact:#{index + 1}",
          payout_id: "batch-file-payout",
          payload: { step: index + 1 }
        )
      end

      journal.append_many(facts)

      assert_equal 1, File.binread(path).lines.length
      assert_equal facts.map { |fact| [fact.sequence, fact.type, fact.fact_id, fact.payload] },
        journal.facts.map { |fact| [fact.sequence, fact.type, fact.fact_id, fact.payload] }
    end
  end

  def test_malformed_record_shapes_are_explicit_durable_corruption
    ["[]", "{\"version\":1}", "{\"version\":1,\"type\":4}"].each do |line|
      assert_raises(RubyRouting::State::DurableCorruptionError) do
        RubyRouting::State::FactCodec.decode_fact(line, line_number: 7)
      end
    end
  end

  def test_file_journal_rejects_non_object_json_roots_as_durable_corruption
    Dir.mktmpdir("ruby-routing-journal-shape") do |directory|
      path = File.join(directory, "facts.jsonl")
      File.binwrite(path, "[]\n")
      journal = RubyRouting::State::FileJournal.new(path)

      assert_raises(RubyRouting::State::DurableCorruptionError) { journal.facts }
    end
  end
end
