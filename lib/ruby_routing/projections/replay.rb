# frozen_string_literal: true

module RubyRouting
  module Projections
    module Replay
      module_function

      def analytics(facts)
        RubyRouting::Projections::Analytics.from_facts(facts)
      end
    end
  end
end
