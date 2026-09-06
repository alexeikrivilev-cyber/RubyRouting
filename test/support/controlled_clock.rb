# frozen_string_literal: true

module TestSupport
  class ControlledClock
    def initialize(start_time: Time.utc(2026, 1, 1, 0, 0, 0))
      unless start_time.is_a?(Time)
        raise ArgumentError, "start_time must be Time"
      end

      @mutex = Thread::Mutex.new
      @current_time = start_time.utc.freeze
      @monotonic = Rational(0, 1)
    end

    def current_time
      @mutex.synchronize { @current_time }
    end

    def now
      current_time
    end

    def monotonic
      @mutex.synchronize { @monotonic }
    end

    def monotonic_reference_for(wall_time)
      unless wall_time.is_a?(Time)
        raise ArgumentError, "monotonic reference requires a Time"
      end

      @mutex.synchronize do
        @monotonic + Rational(wall_time.utc.to_r - @current_time.to_r)
      end
    end

    def advance(seconds)
      unless seconds.is_a?(Numeric) && seconds >= 0
        raise ArgumentError, "seconds must be a non-negative number"
      end

      @mutex.synchronize do
        @current_time = (@current_time + seconds).utc.freeze
        @monotonic += Rational(seconds.to_s)
      end
    end
  end
end
