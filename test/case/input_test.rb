# frozen_string_literal: true

require_relative "../test_helper"

class AuthoritativeCaseInputTest < Minitest::Test
  ROOT = File.expand_path("../../", __dir__)

  def load_dataset(queue: "data/operations_queue_10.json")
    RubyRouting::Case::Input.load(
      providers_path: File.join(ROOT, "data/providers.json"),
      history_path: File.join(ROOT, "data/operations_history.csv"),
      queue_path: File.join(ROOT, queue)
    )
  end

  def test_loads_official_inputs_with_exact_decimal_values
    dataset = load_dataset

    assert_equal 4, dataset.providers.length
    assert_equal 100, dataset.history.length
    assert_equal 10, dataset.operations.length
    assert_instance_of Rational, dataset.providers.first.conversion_24h
    assert_equal Rational(87, 100), dataset.providers.first.conversion_24h
    assert_equal 385_800, dataset.operations.sum(&:amount)
    assert_equal "operations_history.csv", dataset.history_source
  end

  def test_rejects_unknown_provider_fields_at_boundary
    path = Tempfile.new(["providers", ".json"])
    begin
      source = JSON.parse(File.read(File.join(ROOT, "data/providers.json")))
      source["providers"][0]["routing_magic"] = true
      path.write(JSON.generate(source))
      path.close

      error = assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::Input.load(
          providers_path: path.path,
          history_path: File.join(ROOT, "data/operations_history.csv"),
          queue_path: File.join(ROOT, "data/operations_queue_10.json")
        )
      end
      assert_includes error.message, "unknown fields"
    ensure
      path.close unless path.closed?
      path.unlink
    end
  end

  def test_rejects_duplicate_json_keys_at_boundary
    path = Tempfile.new(["providers", ".json"])
    begin
      path.write('{"snapshot_at":"2026-07-30T09:00:00+03:00","snapshot_at":"2026-07-30T09:00:00+03:00"}')
      path.close
      assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::Input.load(
          providers_path: path.path,
          history_path: File.join(ROOT, "data/operations_history.csv"),
          queue_path: File.join(ROOT, "data/operations_queue_10.json")
        )
      end
    ensure
      path.close unless path.closed?
      path.unlink
    end
  end

  def test_rejects_float_values_in_typed_hashes
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Provider.new(
        payment_system: "p", status: "active", traffic_percentage: 1.0, priority: 1,
        limit_amount_min: nil, limit_amount_max: nil, daily_amount_limit: nil,
        daily_approved_amount: 0, in_progress_count_limit: nil, in_progress_count: 0,
        in_progress_amount_limit: nil, in_progress_amount: 0, available_requisites: 1,
        conversion_24h: 1.0, avg_latency_sec: 1, banks: [], exclude_banks: false,
        provider_margin_pct: 0, merchant_margin_pct: 1, allow_negative_agreement: false
      )
    end
    assert_includes error.message, "exact"
  end

  def test_history_card_brand_rejects_non_string_as_input_error
    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::HistoryEntry.new(
        operation_id: "history-1", created_at: Time.utc(2026, 7, 30), amount: 1,
        bank: "bank", card_brand: 123, payment_system: "provider", status: "approved",
        latency_sec: 1
      )
    end
    assert_includes error.message, "card_brand"
  end

  def test_history_source_is_preserved_for_custom_input
    history_path = Tempfile.new(["case-history-custom", ".csv"])
    begin
      history_path.write(File.read(File.join(ROOT, "data/operations_history.csv")))
      history_path.close
      dataset = RubyRouting::Case::Input.load(
        providers_path: File.join(ROOT, "data/providers.json"),
        history_path: history_path.path,
        queue_path: File.join(ROOT, "data/operations_queue_10.json")
      )

      assert_equal File.basename(history_path.path), dataset.history_source
    ensure
      history_path.close unless history_path.closed?
      history_path.unlink
    end
  end

  def test_rejects_queue_that_can_make_temporal_constraints_order_dependent
    path = Tempfile.new(["case-queue-out-of-order", ".json"])
    begin
      operations = JSON.parse(File.read(File.join(ROOT, "data/operations_queue_10.json")))
      path.write(JSON.generate([operations[1], operations[0]]))
      path.close

      error = assert_raises(RubyRouting::Case::InputError) do
        RubyRouting::Case::Input.load_queue(path.path)
      end

      assert_includes error.message, "non-decreasing created_at"
    ensure
      path.close unless path.closed?
      path.unlink
    end
  end

  def test_dataset_rejects_programmatically_constructed_out_of_order_operations
    dataset = load_dataset

    error = assert_raises(RubyRouting::Case::InputError) do
      RubyRouting::Case::Dataset.new(
        snapshot_at: dataset.snapshot_at,
        gateway: dataset.gateway,
        merchant: dataset.merchant,
        providers: dataset.providers,
        history: dataset.history,
        operations: dataset.operations.reverse
      )
    end

    assert_includes error.message, "non-decreasing created_at"
  end
end
