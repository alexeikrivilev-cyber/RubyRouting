# frozen_string_literal: true

module TestSupport
  class ControlledClock
    attr_reader :current_time

    def initialize(start_time: Time.utc(2026, 1, 1, 0, 0, 0))
      unless start_time.is_a?(Time)
        raise ArgumentError, "start_time must be Time"
      end

      @current_time = start_time.utc.freeze
    end

    def now
      current_time
    end

    def advance(seconds)
      unless seconds.is_a?(Numeric) && seconds >= 0
        raise ArgumentError, "seconds must be a non-negative number"
      end

      @current_time = (current_time + seconds).utc.freeze
    end
  end
end
