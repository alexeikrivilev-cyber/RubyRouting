# frozen_string_literal: true

module RubyRouting
  class PayoutIntent
    attr_reader :id, :money, :recipient, :context, :routing_context

    def initialize(id:, money:, recipient: {}, context: {}, routing_context: nil)
      @id = normalize_id(id, "payout id")
      unless money.is_a?(RubyRouting::Money)
        raise ArgumentError, "money must be RubyRouting::Money"
      end

      @money = money
      @recipient = freeze_nested(recipient)
      @context = freeze_nested(context)
      derived_routing_context = RubyRouting::RoutingContext.from(@context)
      if routing_context
        @routing_context = RubyRouting::RoutingContext.from(routing_context)
        unless derived_routing_context.empty? || @routing_context == derived_routing_context
          raise ArgumentError, "routing_context does not match payout context"
        end
      else
        @routing_context = derived_routing_context
      end
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
      RubyRouting::ImmutableData.deep_freeze(value)
    end
  end
end
