# frozen_string_literal: true

require "csv"
require "json"
require "time"

module RubyRouting
  module Case
    class Provider
      STATUSES = %w[active enabled inactive disabled].freeze

      attr_reader :payment_system, :status, :traffic_percentage, :priority,
                  :limit_amount_min, :limit_amount_max, :daily_amount_limit,
                  :daily_approved_amount, :in_progress_count_limit,
                  :in_progress_count, :in_progress_amount_limit,
                  :in_progress_amount, :available_requisites, :conversion_24h,
                  :avg_latency_sec, :banks, :exclude_banks,
                  :provider_margin_pct, :merchant_margin_pct,
                  :allow_negative_agreement, :note

      def initialize(payment_system:, status:, traffic_percentage:, priority:,
                     limit_amount_min:, limit_amount_max:, daily_amount_limit:,
                     daily_approved_amount:, in_progress_count_limit:,
                     in_progress_count:, in_progress_amount_limit:,
                     in_progress_amount:, available_requisites:, conversion_24h:,
                     avg_latency_sec:, banks:, exclude_banks:,
                     provider_margin_pct:, merchant_margin_pct:,
                     allow_negative_agreement:, note: nil)
        @payment_system = Input.assert_id(payment_system, "provider payment_system")
        @status = Input.assert_string(status, "#{@payment_system} status")
        Input.assert_one_of(@status, STATUSES, "#{@payment_system} status")
        @traffic_percentage = Input.assert_percent(traffic_percentage, "#{@payment_system} traffic_percentage")
        @priority = Input.assert_integer(priority, "#{@payment_system} priority", min: 0)
        @limit_amount_min = Input.optional_integer(limit_amount_min, "#{@payment_system} limit_amount_min")
        @limit_amount_max = Input.optional_integer(limit_amount_max, "#{@payment_system} limit_amount_max")
        if @limit_amount_min && @limit_amount_max && @limit_amount_min > @limit_amount_max
          raise InputError, "#{@payment_system} minimum amount exceeds maximum amount"
        end
        @daily_amount_limit = Input.optional_integer(daily_amount_limit, "#{@payment_system} daily_amount_limit")
        @daily_approved_amount = Input.assert_integer(daily_approved_amount, "#{@payment_system} daily_approved_amount", min: 0)
        if @daily_amount_limit && @daily_approved_amount > @daily_amount_limit
          raise InputError, "#{@payment_system} daily approved amount exceeds limit"
        end
        @in_progress_count_limit = Input.optional_integer(in_progress_count_limit, "#{@payment_system} in_progress_count_limit")
        @in_progress_count = Input.assert_integer(in_progress_count, "#{@payment_system} in_progress_count", min: 0)
        if @in_progress_count_limit && @in_progress_count > @in_progress_count_limit
          raise InputError, "#{@payment_system} in-progress count exceeds limit"
        end
        @in_progress_amount_limit = Input.optional_integer(in_progress_amount_limit, "#{@payment_system} in_progress_amount_limit")
        @in_progress_amount = Input.assert_integer(in_progress_amount, "#{@payment_system} in_progress_amount", min: 0)
        if @in_progress_amount_limit && @in_progress_amount > @in_progress_amount_limit
          raise InputError, "#{@payment_system} in-progress amount exceeds limit"
        end
        @available_requisites = Input.assert_integer(available_requisites, "#{@payment_system} available_requisites", min: 0)
        @conversion_24h = Input.assert_ratio(conversion_24h, "#{@payment_system} conversion_24h", min: 0, max: 1)
        @avg_latency_sec = Input.assert_integer(avg_latency_sec, "#{@payment_system} avg_latency_sec", min: 0)
        @banks = Input.assert_string_array(banks, "#{@payment_system} banks")
        @exclude_banks = Input.assert_boolean(exclude_banks, "#{@payment_system} exclude_banks")
        @provider_margin_pct = Input.assert_ratio(provider_margin_pct, "#{@payment_system} provider_margin_pct", min: 0)
        @merchant_margin_pct = Input.assert_ratio(merchant_margin_pct, "#{@payment_system} merchant_margin_pct", min: 0)
        @allow_negative_agreement = Input.assert_boolean(allow_negative_agreement, "#{@payment_system} allow_negative_agreement")
        @note = note.nil? ? nil : Input.assert_string(note, "#{@payment_system} note")
        freeze
      end

      def active?
        status == "active"
      end

      def to_h
        {
          payment_system: payment_system,
          status: status,
          traffic_percentage: traffic_percentage,
          priority: priority,
          limit_amount_min: limit_amount_min,
          limit_amount_max: limit_amount_max,
          daily_amount_limit: daily_amount_limit,
          daily_approved_amount: daily_approved_amount,
          in_progress_count_limit: in_progress_count_limit,
          in_progress_count: in_progress_count,
          in_progress_amount_limit: in_progress_amount_limit,
          in_progress_amount: in_progress_amount,
          available_requisites: available_requisites,
          conversion_24h: conversion_24h,
          avg_latency_sec: avg_latency_sec,
          banks: banks,
          exclude_banks: exclude_banks,
          provider_margin_pct: provider_margin_pct,
          merchant_margin_pct: merchant_margin_pct,
          allow_negative_agreement: allow_negative_agreement,
          note: note
        }.freeze
      end
    end

    class Operation
      attr_reader :operation_id, :created_at, :amount, :bank, :card_brand,
                  :payout_requisite

      def initialize(operation_id:, created_at:, amount:, bank:, card_brand:, payout_requisite:)
        @operation_id = Input.assert_id(operation_id, "operation_id")
        @created_at = Input.assert_time(created_at, "#{@operation_id} created_at")
        @amount = Input.assert_integer(amount, "#{@operation_id} amount", min: 1)
        @bank = Input.assert_string(bank, "#{@operation_id} bank")
        @card_brand = card_brand.nil? ? nil : Input.assert_string(card_brand, "#{@operation_id} card_brand")
        @payout_requisite = Input.assert_object(payout_requisite, "#{@operation_id} payout_requisite")
        raise InputError, "#{@operation_id} payout_requisite must not be empty" if @payout_requisite.empty?
        freeze
      end

      def to_h
        {
          operation_id: operation_id,
          created_at: created_at.iso8601,
          amount: amount,
          bank: bank,
          card_brand: card_brand,
          payout_requisite: payout_requisite
        }.freeze
      end
    end

    class HistoryEntry
      STATUSES = %w[approved rejected expired].freeze
      attr_reader :operation_id, :created_at, :amount, :bank, :card_brand,
                  :payment_system, :status, :latency_sec

      def initialize(operation_id:, created_at:, amount:, bank:, card_brand:,
                     payment_system:, status:, latency_sec:)
        @operation_id = Input.assert_id(operation_id, "history operation_id")
        @created_at = Input.assert_time(created_at, "#{@operation_id} history created_at")
        @amount = Input.assert_integer(amount, "#{@operation_id} history amount", min: 1)
        @bank = Input.assert_string(bank, "#{@operation_id} history bank")
        @card_brand = if card_brand.nil? || (card_brand.is_a?(String) && card_brand.empty?)
          nil
        else
          Input.assert_string(card_brand, "#{@operation_id} history card_brand")
        end
        @payment_system = Input.assert_id(payment_system, "#{@operation_id} history payment_system")
        @status = Input.assert_string(status, "#{@operation_id} history status")
        Input.assert_one_of(@status, STATUSES, "#{@operation_id} history status")
        @latency_sec = Input.assert_integer(latency_sec, "#{@operation_id} history latency_sec", min: 0)
        freeze
      end
    end

    class Dataset
      attr_reader :snapshot_at, :gateway, :merchant, :providers, :history,
                  :operations, :history_source, :business_calendar

      def initialize(snapshot_at:, gateway:, merchant:, providers:, history:, operations:,
                     history_source: "operations_history.csv")
        @business_calendar = BusinessCalendar.from(snapshot_at)
        @snapshot_at = Input.assert_time(snapshot_at, "snapshot_at")
        @gateway = Input.assert_string(gateway, "gateway")
        @merchant = Input.assert_string(merchant, "merchant")
        @providers = Input.assert_unique_ids(providers, "providers")
        @history = Input.assert_unique_ids(history, "history")
        @operations = Input.assert_unique_ids(operations, "operations")
        Input.assert_chronological_operations(@operations)
        @history_source = Input.assert_string(history_source, "history source")
        raise InputError, "history source must be non-empty" if @history_source.empty?
        freeze
      end
    end

    module Input
      module_function

      def load(providers_path:, history_path:, queue_path:)
        providers_document = load_json(providers_path, "providers")
        history = load_history(history_path)
        operations = load_queue(queue_path)
        provider_root = assert_hash(providers_document, "providers root")
        keys!(provider_root, required: %w[snapshot_at gateway merchant providers], optional: [], context: "providers root")
        provider_values = provider_root.fetch("providers")
        unless provider_values.is_a?(Array)
          raise InputError, "providers root providers must be an Array"
        end
        providers = provider_values.map.with_index { |value, index| parse_provider(value, index) }
        Dataset.new(
          snapshot_at: provider_root.fetch("snapshot_at"),
          gateway: assert_string(provider_root.fetch("gateway"), "gateway"),
          merchant: assert_string(provider_root.fetch("merchant"), "merchant"),
          providers: providers,
          history: history,
          operations: operations,
          history_source: File.basename(history_path.to_s)
        )
      end

      def load_json(path, label)
        text = File.read(path)
        # JSON's decimal_class keeps every non-integral business value exact;
        # parsing to Float first would make the boundary lossy.
        JSON.parse(text, decimal_class: Rational, create_additions: false, allow_duplicate_key: false)
      rescue Errno::ENOENT => error
        raise InputError, "#{label} file not found: #{error.message}"
      rescue JSON::ParserError => error
        raise InputError, "#{label} JSON is invalid: #{error.message}"
      rescue SystemCallError => error
        raise InputError, "#{label} file cannot be read: #{error.message}"
      end

      def load_history(path)
        text = File.read(path)
        table = CSV.parse(text, headers: true, return_headers: false)
        expected = %w[operation_id created_at amount bank card_brand payment_system status latency_sec]
        actual = table.headers
        unless actual == expected
          raise InputError, "history CSV header must be #{expected.join(',')}, got #{actual.inspect}"
        end
        table.map.with_index do |row, index|
          HistoryEntry.new(
            operation_id: row["operation_id"],
            created_at: row["created_at"],
            amount: parse_integer(row["amount"], "history row #{index + 2} amount"),
            bank: row["bank"],
            card_brand: row["card_brand"],
            payment_system: row["payment_system"],
            status: row["status"],
            latency_sec: parse_integer(row["latency_sec"], "history row #{index + 2} latency_sec")
          )
        end
      rescue Errno::ENOENT => error
        raise InputError, "history file not found: #{error.message}"
      rescue CSV::MalformedCSVError => error
        raise InputError, "history CSV is invalid: #{error.message}"
      end

      def load_queue(path)
        value = load_json(path, "queue")
        unless value.is_a?(Array)
          raise InputError, "queue root must be an Array"
        end
        operations = value.map.with_index { |operation, index| parse_operation(operation, index) }
        assert_chronological_operations(operations)
      end

      def assert_chronological_operations(operations)
        if operations.each_cons(2).any? { |previous, current| current.created_at < previous.created_at }
          raise InputError, "queue operations must be ordered by non-decreasing created_at"
        end
        operations
      end

      def parse_provider(value, index)
        value = assert_hash(value, "provider #{index}")
        required = %w[payment_system status traffic_percentage priority limit_amount_min limit_amount_max daily_amount_limit daily_approved_amount in_progress_count_limit in_progress_count in_progress_amount_limit in_progress_amount available_requisites conversion_24h avg_latency_sec banks exclude_banks provider_margin_pct merchant_margin_pct allow_negative_agreement]
        keys!(value, required: required, optional: ["note"], context: "provider #{index}")
        Provider.new(
          payment_system: value.fetch("payment_system"), status: value.fetch("status"),
          traffic_percentage: value.fetch("traffic_percentage"), priority: value.fetch("priority"),
          limit_amount_min: value.fetch("limit_amount_min"), limit_amount_max: value.fetch("limit_amount_max"),
          daily_amount_limit: value.fetch("daily_amount_limit"), daily_approved_amount: value.fetch("daily_approved_amount"),
          in_progress_count_limit: value.fetch("in_progress_count_limit"), in_progress_count: value.fetch("in_progress_count"),
          in_progress_amount_limit: value.fetch("in_progress_amount_limit"), in_progress_amount: value.fetch("in_progress_amount"),
          available_requisites: value.fetch("available_requisites"), conversion_24h: value.fetch("conversion_24h"),
          avg_latency_sec: value.fetch("avg_latency_sec"), banks: value.fetch("banks"),
          exclude_banks: value.fetch("exclude_banks"), provider_margin_pct: value.fetch("provider_margin_pct"),
          merchant_margin_pct: value.fetch("merchant_margin_pct"), allow_negative_agreement: value.fetch("allow_negative_agreement"),
          note: value["note"]
        )
      rescue ArgumentError => error
        raise InputError, "provider #{index}: #{error.message}"
      end

      def parse_operation(value, index)
        value = assert_hash(value, "queue operation #{index}")
        keys!(value, required: %w[operation_id created_at amount bank card_brand payout_requisite], optional: [], context: "queue operation #{index}")
        Operation.new(
          operation_id: value.fetch("operation_id"), created_at: value.fetch("created_at"),
          amount: value.fetch("amount"), bank: value.fetch("bank"), card_brand: value.fetch("card_brand"),
          payout_requisite: value.fetch("payout_requisite")
        )
      rescue ArgumentError => error
        raise InputError, "queue operation #{index}: #{error.message}"
      end

      def assert_hash(value, label)
        raise InputError, "#{label} must be an object" unless value.is_a?(Hash)
        value
      end

      def keys!(value, required:, optional:, context:)
        keys = value.keys
        unless keys.all? { |key| key.is_a?(String) }
          raise InputError, "#{context} keys must be strings"
        end
        missing = required - keys
        unknown = keys - required - optional
        raise InputError, "#{context} missing fields: #{missing.join(', ')}" unless missing.empty?
        raise InputError, "#{context} unknown fields: #{unknown.join(', ')}" unless unknown.empty?
      end

      def assert_id(value, label)
        unless value.is_a?(String) || value.is_a?(Symbol)
          raise InputError, "#{label} must be a non-empty String or Symbol"
        end
        text = value.to_s.strip
        raise InputError, "#{label} must be non-empty" if text.empty?
        text.freeze
      end

      def assert_string(value, label)
        raise InputError, "#{label} must be a String" unless value.is_a?(String)
        value.freeze
      end

      def assert_time(value, label)
        return value.utc.freeze if value.is_a?(Time)
        raise InputError, "#{label} must be an ISO-8601 timestamp" unless value.is_a?(String)
        Time.iso8601(value).utc.freeze
      rescue ArgumentError => error
        raise InputError, "#{label} is invalid: #{error.message}"
      end

      def assert_integer(value, label, min: nil)
        raise InputError, "#{label} must be an Integer" unless value.is_a?(Integer)
        raise InputError, "#{label} must be >= #{min}" if min && value < min
        value
      end

      def optional_integer(value, label)
        return nil if value.nil?
        assert_integer(value, label, min: 0)
      end

      def assert_ratio(value, label, min: nil, max: nil)
        unless value.is_a?(Integer) || value.is_a?(Rational)
          raise InputError, "#{label} must be an exact Integer or Rational"
        end
        raise InputError, "#{label} must be >= #{min}" if min && value < min
        raise InputError, "#{label} must be <= #{max}" if max && value > max
        value
      end

      def assert_percent(value, label)
        assert_ratio(value, label, min: 0, max: 100)
      end

      def assert_boolean(value, label)
        raise InputError, "#{label} must be boolean" unless value == true || value == false
        value
      end

      def assert_string_array(value, label)
        raise InputError, "#{label} must be an Array" unless value.is_a?(Array)
        values = value.map { |item| assert_id(item, label) }
        raise InputError, "#{label} contains duplicates" unless values.uniq.length == values.length
        values.freeze
      end

      def assert_object(value, label)
        raise InputError, "#{label} must be an object" unless value.is_a?(Hash)
        deep_freeze(value)
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), copy|
            unless key.is_a?(String) || key.is_a?(Symbol)
              raise InputError, "object keys must be strings or symbols"
            end
            copy[key.freeze] = deep_freeze(nested)
          end.freeze
        when Array
          value.map { |nested| deep_freeze(nested) }.freeze
        when String
          value.freeze
        when Integer, Rational, Symbol, TrueClass, FalseClass, NilClass
          value
        else
          raise InputError, "unsupported value in object: #{value.class}"
        end
      end

      def parse_integer(value, label)
        raise InputError, "#{label} must be an integer CSV value" unless value.is_a?(String) && value.match?(/\A\d+\z/)
        value.to_i
      end

      def assert_one_of(value, allowed, label)
        raise InputError, "#{label} must be one of #{allowed.join(', ')}" unless allowed.include?(value)
        value
      end

      def assert_unique_ids(values, label)
        values = values.dup.freeze
        ids = values.map { |value| value.respond_to?(:operation_id) ? value.operation_id : value.payment_system }
        raise InputError, "#{label} contains duplicate identities" unless ids.uniq.length == ids.length
        values
      end
    end
  end
end
