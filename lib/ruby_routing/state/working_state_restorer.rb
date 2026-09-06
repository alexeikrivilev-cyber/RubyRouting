# frozen_string_literal: true

module RubyRouting
  module State
    # Owns the ordered durable-prefix replay protocol. Fact reducers remain
    # supplied by the coordinator for now, while this seam owns replay order,
    # runtime-catalog validation and the explicit corruption boundary.
    class WorkingStateRestorer
      def initialize(prepare_catalog:, current_catalog:, restore_fact:, validate_state:)
        @prepare_catalog = prepare_catalog
        @current_catalog = current_catalog
        @restore_fact = restore_fact
        @validate_state = validate_state
      end

      def restore!(facts:, opportunities:)
        supplied_catalog = RubyRouting::State::ProviderCatalogLedger.new(opportunities: opportunities)
        @prepare_catalog.call
        facts.sort_by(&:sequence).each do |fact|
          begin
            @restore_fact.call(fact)
          rescue RubyRouting::State::DurableCorruptionError
            raise
          rescue ArgumentError, KeyError, TypeError, NoMethodError => error
            raise RubyRouting::State::DurableCorruptionError,
              "fact #{fact.sequence} cannot restore working state: #{error.message}"
          end
        end
        supplied_catalog.provider_ids.each do |provider_id|
          next if @current_catalog.call.key?(provider_id)

          raise ArgumentError,
            "supplied opportunity #{provider_id} is not current in durable provider history"
        end
        @validate_state.call
        nil
      end
    end
  end
end
