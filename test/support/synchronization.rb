# frozen_string_literal: true

module TestSupport
  module Synchronization
    class Barrier
      def initialize(parties)
        unless parties.is_a?(Integer) && parties.positive?
          raise ArgumentError, "parties must be a positive Integer"
        end

        @parties = parties
        @arrived = 0
        @generation = 0
        @mutex = Thread::Mutex.new
        @condition = ConditionVariable.new
      end

      def wait
        @mutex.synchronize do
          generation = @generation
          @arrived += 1
          if @arrived == @parties
            @generation += 1
            @arrived = 0
            @condition.broadcast
          else
            @condition.wait(@mutex) while generation == @generation
          end
        end
        nil
      end
    end
  end
end
