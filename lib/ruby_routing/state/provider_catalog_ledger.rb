# frozen_string_literal: true

module RubyRouting
  module State
    # Owns the current functional provider catalog and its ordered registration
    # timeline. The coordinator remains the atomic facade and owns fact
    # publication; this ledger only answers catalog identity/currentness
    # questions and never performs provider I/O.
    class ProviderCatalogLedger
      def initialize(opportunities: [])
        @opportunities = {}
        @timeline = Hash.new { |entries, provider_id| entries[provider_id] = [] }
        replace_current!(opportunities)
      end

      def current
        @opportunities.values.sort_by(&:provider_id).freeze
      end

      def provider_ids
        @opportunities.keys.sort.freeze
      end

      def fetch(provider_id, &block)
        @opportunities.fetch(normalize_id(provider_id), &block)
      end

      def key?(provider_id)
        @opportunities.key?(normalize_id(provider_id))
      end

      def register(opportunity, sequence:)
        validate_opportunity!(opportunity)
        validate_sequence!(sequence)
        validate_timeline_progress!(opportunity.provider_id, sequence)
        @opportunities[opportunity.provider_id] = opportunity
        @timeline[opportunity.provider_id] << [:registered, sequence]
        opportunity
      end

      def remove(provider_id, sequence:)
        normalized = normalize_id(provider_id)
        validate_sequence!(sequence)
        validate_timeline_progress!(normalized, sequence)
        unless @opportunities.delete(normalized)
          raise KeyError, "provider opportunity is not currently registered: #{normalized}"
        end

        @timeline[normalized] << [:removed, sequence]
        normalized
      end

      def replace_current(opportunity)
        validate_opportunity!(opportunity)
        unless @opportunities.key?(opportunity.provider_id)
          raise KeyError, "provider opportunity is not currently registered: #{opportunity.provider_id}"
        end

        @opportunities[opportunity.provider_id] = opportunity
        opportunity
      end

      def registered_before?(provider_id, sequence:)
        validate_sequence!(sequence)
        @timeline.fetch(normalize_id(provider_id), []).any? do |kind, event_sequence|
          kind == :registered && event_sequence < sequence
        end
      end

      def current_before?(provider_id, sequence:)
        validate_sequence!(sequence)
        current = false
        @timeline.fetch(normalize_id(provider_id), []).each do |kind, event_sequence|
          break if event_sequence >= sequence

          current = kind == :registered
        end
        current
      end

      private

      def replace_current!(opportunities)
        normalized = normalize_opportunities(opportunities)
        @opportunities = normalized.to_h { |opportunity| [opportunity.provider_id, opportunity] }
        self
      end

      def normalize_opportunities(opportunities)
        values = RubyRouting::Collection.to_array(opportunities, "opportunities")
        values.each { |opportunity| validate_opportunity!(opportunity) }
        ids = values.map(&:provider_id)
        unless ids.uniq.length == ids.length
          raise ArgumentError, "provider opportunities must have unique ids"
        end

        values
      end

      def validate_opportunity!(opportunity)
        return if opportunity.is_a?(RubyRouting::ProviderOpportunity)

        raise ArgumentError, "opportunities must contain ProviderOpportunity values"
      end

      def validate_sequence!(sequence)
        return if sequence.is_a?(Integer) && sequence.positive?

        raise ArgumentError, "catalog timeline sequence must be a positive Integer"
      end

      def validate_timeline_progress!(provider_id, sequence)
        previous_sequence = @timeline.fetch(provider_id, []).last&.last
        return if previous_sequence.nil? || sequence > previous_sequence

        raise ArgumentError, "catalog timeline sequence must advance for #{provider_id}"
      end

      def normalize_id(provider_id)
        RubyRouting::Identity.normalize(provider_id, "provider id")
      end
    end
  end
end
