# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require "digest"

module RubyRouting
  module State
    class DurableCorruptionError < StandardError; end

    module FactCodec
      VERSION = 1
      module_function

      def encode_fact(fact)
        unless fact.is_a?(RubyRouting::Fact)
          raise ArgumentError, "fact must be RubyRouting::Fact"
        end

        body = {
          "version" => VERSION,
          "sequence" => fact.sequence,
          "type" => fact.type.to_s,
          "fact_id" => fact.fact_id,
          "payout_id" => fact.payout_id,
          "payload" => encode_value(fact.payload)
        }
        JSON.generate(body.merge("checksum" => Digest::SHA256.hexdigest(JSON.generate(body))))
      end

      def encode_batch(facts)
        normalized = RubyRouting::Collection.to_array(facts, "facts")
        unless normalized.all? { |fact| fact.is_a?(RubyRouting::Fact) }
          raise ArgumentError, "facts must contain RubyRouting::Fact values"
        end
        raise ArgumentError, "fact batch must not be empty" if normalized.empty?

        body = {
          "version" => VERSION,
          "kind" => "batch",
          "facts" => normalized.map { |fact| JSON.parse(encode_fact(fact)) }
        }
        JSON.generate(body.merge("checksum" => Digest::SHA256.hexdigest(JSON.generate(body))))
      end

      def decode_fact(line, line_number: nil)
        record = JSON.parse(line, allow_duplicate_key: false)
        validate_exact_keys!(
          record,
          %w[version sequence type fact_id payout_id payload checksum],
          "fact envelope"
        )
        body = {
          "version" => record.fetch("version"),
          "sequence" => record.fetch("sequence"),
          "type" => record.fetch("type"),
          "fact_id" => record.fetch("fact_id"),
          "payout_id" => record.fetch("payout_id"),
          "payload" => record.fetch("payload")
        }
        checksum = record.fetch("checksum")
        expected = Digest::SHA256.hexdigest(JSON.generate(body))
        raise DurableCorruptionError, "fact line #{line_number} checksum mismatch" unless checksum == expected
        raise DurableCorruptionError, "fact line #{line_number} has unsupported version" unless body["version"] == VERSION
        validate_fact_envelope!(body)

        type_name = body.fetch("type")
        unless type_name.is_a?(String) && RubyRouting::Fact::TYPES.any? { |type| type.to_s == type_name }
          raise DurableCorruptionError, "fact line #{line_number} has unsupported fact type"
        end

        RubyRouting::Fact.new(
          sequence: body.fetch("sequence"),
          type: RubyRouting::Fact::TYPES.find { |type| type.to_s == type_name },
          fact_id: body.fetch("fact_id"),
          payout_id: body.fetch("payout_id"),
          payload: decode_value(body.fetch("payload"))
        )
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError,
             Encoding::CompatibilityError, ZeroDivisionError => error
        raise DurableCorruptionError, "fact line #{line_number} is malformed: #{error.message}"
      end

      def decode_batch(line, line_number: nil)
        record = JSON.parse(line, allow_duplicate_key: false)
        validate_exact_keys!(
          record,
          %w[version kind facts checksum],
          "fact batch envelope"
        )
        body = {
          "version" => record.fetch("version"),
          "kind" => record.fetch("kind"),
          "facts" => record.fetch("facts")
        }
        checksum = record.fetch("checksum")
        expected = Digest::SHA256.hexdigest(JSON.generate(body))
        raise DurableCorruptionError, "fact batch #{line_number} checksum mismatch" unless checksum == expected
        raise DurableCorruptionError, "fact batch #{line_number} has unsupported version" unless body["version"] == VERSION
        raise DurableCorruptionError, "fact line #{line_number} is not a batch" unless body["kind"] == "batch"
        unless body["facts"].is_a?(Array) && !body["facts"].empty?
          raise DurableCorruptionError, "fact batch #{line_number} must contain facts"
        end

        body["facts"].map do |fact_record|
          decode_fact(JSON.generate(fact_record), line_number: line_number)
        end.freeze
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError,
             Encoding::CompatibilityError, ZeroDivisionError => error
        raise DurableCorruptionError, "fact batch #{line_number} is malformed: #{error.message}"
      end

      def encode_value(value)
        case value
        when NilClass, TrueClass, FalseClass, String, Integer
          value
        when Symbol
          { "$type" => "symbol", "value" => value.to_s }
        when Rational
          { "$type" => "rational", "numerator" => value.numerator, "denominator" => value.denominator }
        when Time
          { "$type" => "time", "value" => value.iso8601(9) }
        when RubyRouting::Money
          {
            "$type" => "money",
            "amount_minor" => value.amount_minor,
            "currency" => value.currency
          }
        when Hash
          {
            "$type" => "hash",
            "entries" => value.map { |key, nested| [encode_value(key), encode_value(nested)] }
          }
        when Array
          { "$type" => "array", "items" => value.map { |nested| encode_value(nested) } }
        else
          raise ArgumentError, "unsupported durable fact value #{value.class}"
        end
      end
      private_class_method :encode_value

      def decode_value(value)
        if value.is_a?(Float)
          raise ArgumentError, "floating point durable values are unsupported"
        end

        unless value.is_a?(Hash)
          return durable_string(value) if value.is_a?(String)
          return value.map { |nested| decode_value(nested) } if value.is_a?(Array)

          return value
        end

        type = value.fetch("$type")
        case type
        when "symbol"
          validate_tagged_value_fields!(value, %w[$type value], "symbol")
          symbol_name = value.fetch("value")
          unless symbol_name.is_a?(String) && symbol_name == symbol_name.strip && !symbol_name.empty?
            raise ArgumentError, "durable symbol value must be a canonical non-empty String"
          end

          # Reuse an already-loaded closed-domain symbol without interning
          # attacker-controlled names. Unknown symbol values remain strings;
          # external/provider identifiers are strings at the domain boundary.
          Symbol.all_symbols.find { |symbol| symbol.to_s == symbol_name } || durable_string(symbol_name)
        when "rational"
          validate_tagged_value_fields!(value, %w[$type numerator denominator], "rational")
          numerator = value.fetch("numerator")
          denominator = value.fetch("denominator")
          unless numerator.is_a?(Integer) && denominator.is_a?(Integer)
            raise ArgumentError, "durable rational components must be integers"
          end
          Rational(numerator, denominator)
        when "time"
          validate_tagged_value_fields!(value, %w[$type value], "time")
          Time.iso8601(value.fetch("value")).utc
        when "money"
          validate_tagged_value_fields!(value, %w[$type amount_minor currency], "money")
          amount_minor = value.fetch("amount_minor")
          unless amount_minor.is_a?(Integer)
            raise ArgumentError, "durable money amount must be an integer"
          end
          RubyRouting::Money.new(amount_minor, value.fetch("currency"))
        when "hash"
          validate_tagged_value_fields!(value, %w[$type entries], "hash")
          entries = value.fetch("entries")
          unless entries.is_a?(Array)
            raise ArgumentError, "durable hash entries must be an Array"
          end

          entries.each_with_object({}) do |entry, copy|
            unless entry.is_a?(Array) && entry.length == 2
              raise ArgumentError, "durable hash entry must contain two values"
            end
            key = decode_value(entry.fetch(0))
            if copy.key?(key)
              raise ArgumentError, "durable hash contains duplicate key"
            end

            copy[key] = decode_value(entry.fetch(1))
          end
        when "array"
          validate_tagged_value_fields!(value, %w[$type items], "array")
          value.fetch("items").map { |nested| decode_value(nested) }
        else
          raise ArgumentError, "unsupported durable fact value tag #{type.inspect}"
        end
      end
      private_class_method :decode_value

      def validate_fact_envelope!(body)
        sequence = body.fetch("sequence")
        unless sequence.is_a?(Integer) && sequence.positive?
          raise ArgumentError, "durable fact sequence must be a positive Integer"
        end

        %w[type fact_id payout_id].each do |key|
          value = body.fetch(key)
          unless value.is_a?(String) && !value.empty? && value == value.strip
            raise ArgumentError, "durable fact #{key} must be a canonical non-empty String"
          end
        end
      end
      private_class_method :validate_fact_envelope!

      def validate_exact_keys!(value, expected_keys, label)
        unless value.is_a?(Hash) && value.keys.sort == expected_keys.sort
          raise ArgumentError, "#{label} contains unsupported or missing fields"
        end
      end
      private_class_method :validate_exact_keys!

      def validate_tagged_value_fields!(value, expected_keys, label)
        validate_exact_keys!(value, expected_keys, "durable #{label} value")
      end
      private_class_method :validate_tagged_value_fields!

      def durable_string(value)
        return value.encode(Encoding::US_ASCII) if value.ascii_only?

        value.encode(Encoding::UTF_8)
      end
      private_class_method :durable_string
    end

    class FileJournal
      attr_reader :path

      def initialize(path)
        @path = File.expand_path(path.to_s)
        raise ArgumentError, "journal path must be non-empty" if path.to_s.strip.empty?

        @mutex = Thread::Mutex.new
        @poisoned_reason = nil
        FileUtils.mkdir_p(File.dirname(@path))
      rescue SystemCallError => error
        raise ArgumentError, "cannot create journal directory: #{error.message}"
      end

      def append(fact)
        append_many([fact])
        fact
      end

      def append_many(facts)
        normalized = RubyRouting::Collection.to_array(facts, "journal facts")
        unless normalized.all? { |fact| fact.is_a?(RubyRouting::Fact) }
          raise ArgumentError, "journal facts must contain RubyRouting::Fact values"
        end

        return normalized if normalized.empty?

        line = RubyRouting::State::FactCodec.encode_batch(normalized)
        @mutex.synchronize do
          ensure_usable!
          File.open(path, "ab") do |file|
            file.write(line)
            file.write("\n")
            file.flush
            file.fsync
          end
        end
        normalized
      rescue SystemCallError => error
        raise IOError, "cannot append durable fact: #{error.message}"
      end

      def poison!(reason)
        @mutex.synchronize do
          @poisoned_reason = reason.to_s.freeze
        end
        nil
      end

      def facts
        @mutex.synchronize do
          ensure_usable!
          return [].freeze unless File.file?(path)

          contents = File.binread(path)
          return [].freeze if contents.empty?

          lines = contents.split("\n", -1)
          unless lines.last.empty?
            raise DurableCorruptionError, "journal ends with a truncated fact line"
          end
          lines.pop
          decoded = lines.each_with_index.flat_map do |line, index|
            raise DurableCorruptionError, "fact line #{index + 1} is blank" if line.empty?

            record = JSON.parse(line, allow_duplicate_key: false)
            unless record.is_a?(Hash)
              raise DurableCorruptionError, "fact line #{index + 1} must contain a JSON object"
            end
            if record["kind"] == "batch"
              RubyRouting::State::FactCodec.decode_batch(line, line_number: index + 1)
            else
              [RubyRouting::State::FactCodec.decode_fact(line, line_number: index + 1)]
            end
          end
          validate_sequence!(decoded)
          decoded.freeze
        end
      rescue SystemCallError => error
        raise IOError, "cannot read durable journal: #{error.message}"
      rescue JSON::ParserError => error
        raise DurableCorruptionError, "journal contains malformed JSON: #{error.message}"
      end

      private

      def ensure_usable!
        return unless @poisoned_reason

        raise DurableCorruptionError, "journal is unusable: #{@poisoned_reason}"
      end

      def validate_sequence!(facts)
        facts.each_with_index do |fact, index|
          expected_sequence = index + 1
          unless fact.sequence == expected_sequence && fact.fact_id == "fact:#{expected_sequence}"
            raise DurableCorruptionError, "journal sequence discontinuity at line #{expected_sequence}"
          end
        end
      end
    end
  end
end
