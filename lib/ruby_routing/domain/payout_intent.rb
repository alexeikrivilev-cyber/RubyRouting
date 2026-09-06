# frozen_string_literal: true

module RubyRouting
  class PayoutIntent
    attr_reader :id, :money, :recipient, :context

    def initialize(id:, money:, recipient: {}, context: {})
      @id = normalize_id(id, "payout id")
      unless money.is_a?(RubyRouting::Money)
        raise ArgumentError, "money must be RubyRouting::Money"
      end

      @money = money
      @recipient = freeze_nested(recipient)
      @context = freeze_nested(context)
      freeze
    end

    private

    def normalize_id(value, label)
      unless value.is_a?(String) && !value.strip.empty?
        raise ArgumentError, "#{label} must be a non-empty String"
      end

      value.strip.freeze
    end

    def freeze_nested(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), copy|
          copy[freeze_nested(key)] = freeze_nested(nested)
        end.freeze
      when Array
        value.map { |nested| freeze_nested(nested) }.freeze
      when String
        value.dup.freeze
      else
        if value.respond_to?(:each)
          RubyRouting::Collection.to_array(value, "intent nested collection")
            .map { |nested| freeze_nested(nested) }.freeze
        else
          value.freeze
        end
      end
    end
  end
end
