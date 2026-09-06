# frozen_string_literal: true

require_relative "../test_helper"
require "digest"
require "json"
require "tmpdir"

class DurableCorruptionCampaignTest < Minitest::Test
  CORRUPTION_SEED = 20_260_829

  def test_seeded_corruption_matrix_never_silently_accepts_or_drops_history
    mutations = {
      truncated_line: ->(line) { line[0...-1] },
      malformed_json: ->(_line) { '{"version":1,"kind":"batch"' },
      non_object_root: ->(_line) { "[]" },
      outer_checksum: ->(line) { JSON.generate(JSON.parse(line).merge("checksum" => "0")) },
      unsupported_version: ->(line) { resign_batch(JSON.parse(line).merge("version" => 99)) },
      wrong_record_kind: ->(line) { resign_batch(JSON.parse(line).merge("kind" => "fact")) },
      empty_batch: ->(line) { resign_batch(JSON.parse(line).merge("facts" => [])) },
      missing_outer_checksum: ->(line) {
        JSON.generate(JSON.parse(line).reject { |key, _value| key == "checksum" })
      },
      inner_checksum: ->(line) { mutate_first_fact(line) { |fact| fact.merge("checksum" => "0") } },
      unsupported_inner_tag: ->(line) {
        mutate_first_fact(line) { |fact| resign_fact(fact.merge("payload" => { "$type" => "unknown-tag" })) }
      },
      sequence_discontinuity: ->(line) {
        mutate_first_fact(line) { |fact| resign_fact(fact.merge("sequence" => 9)) }
      },
      fact_identity_discontinuity: ->(line) {
        mutate_first_fact(line) { |fact| resign_fact(fact.merge("fact_id" => "fact:99")) }
      },
      duplicated_batch: ->(line) { "#{line}\n#{line}" },
      blank_record: ->(line) { "#{line}\n" }
    }

    mutations.each do |name, mutation|
      Dir.mktmpdir("ruby-routing-corruption-") do |directory|
        path = File.join(directory, "facts.jsonl")
        journal = RubyRouting::State::FileJournal.new(path)
        File.binwrite(path, "#{mutation.call(valid_batch_line)}\n")

        error = assert_raises(RubyRouting::State::DurableCorruptionError,
                              "seed=#{CORRUPTION_SEED} mutation=#{name}") do
          journal.facts
        end
        refute_empty error.message, "seed=#{CORRUPTION_SEED} mutation=#{name}"
      end
    end

    assert_equal 14, mutations.length
  end

  private

  def valid_batch_line
    RubyRouting::State::FactCodec.encode_batch([
      RubyRouting::Fact.new(
        sequence: 1,
        type: :intent_registered,
        fact_id: "fact:1",
        payout_id: "corruption-campaign",
        payload: { money: RubyRouting::Money.new(100, "RUB") }
      ),
      RubyRouting::Fact.new(
        sequence: 2,
        type: :payout_state_changed,
        fact_id: "fact:2",
        payout_id: "corruption-campaign",
        payload: { status: :pending }
      )
    ])
  end

  def mutate_first_fact(line)
    record = JSON.parse(line)
    first = yield(record.fetch("facts").first)
    resign_batch(record.merge("facts" => [first] + record.fetch("facts").drop(1)))
  end

  def resign_fact(record)
    body = record.reject { |key, _value| key == "checksum" }
    record.merge("checksum" => Digest::SHA256.hexdigest(JSON.generate(body)))
  end

  def resign_batch(record)
    body = record.reject { |key, _value| key == "checksum" }
    JSON.generate(record.merge("checksum" => Digest::SHA256.hexdigest(JSON.generate(body))))
  end
end
