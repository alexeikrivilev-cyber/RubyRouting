# frozen_string_literal: true

module RubyRouting
  module State
    # Wall-clock audit timestamps and monotonic elapsed measurements share one
    # narrow boundary. A wall timestamp may be translated to the current
    # process' monotonic timeline only while restoring durable evidence; the
    # routing core compares monotonic values, never wall-clock differences.
    class SystemClock
      def initialize
        @wall_origin = Time.now.utc.freeze
        @monotonic_origin = raw_monotonic
      end

      def now
        Time.now.utc
      end

      def monotonic
        Rational(raw_monotonic, 1_000_000_000)
      end

      # This is a restore-boundary translation for wall timestamps persisted
      # by an earlier process. It is not used as a wall-clock duration
      # calculation by the coordinator.
      def monotonic_reference_for(wall_time)
        unless wall_time.is_a?(Time)
          raise ArgumentError, "monotonic reference requires a Time"
        end

        @monotonic_origin + Rational(wall_time.utc.to_r - @wall_origin.to_r)
      end

      private

      def raw_monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      end
    end
  end
end
