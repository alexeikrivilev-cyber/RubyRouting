# frozen_string_literal: true

require "time"

module RubyRouting
  module Case
    # The bounded Case calendar separates the business date used by daily
    # limits and reports from the absolute instant used for ordering and RPM.
    # It intentionally stores only the authoritative snapshot offset; it does
    # not consult process timezone state or an external timezone database.
    class BusinessCalendar
      attr_reader :utc_offset_seconds

      def initialize(utc_offset_seconds:)
        unless utc_offset_seconds.is_a?(Integer)
          raise InputError, "business calendar UTC offset must be an Integer"
        end
        unless utc_offset_seconds > -86_400 && utc_offset_seconds < 86_400
          raise InputError, "business calendar UTC offset is out of range"
        end

        @utc_offset_seconds = utc_offset_seconds
        freeze
      end

      def self.from(value)
        time = if value.is_a?(Time)
          value
        elsif value.is_a?(String)
          Time.iso8601(value)
        else
          raise InputError, "business calendar source must be an ISO-8601 timestamp or Time"
        end
        new(utc_offset_seconds: time.utc_offset)
      rescue ArgumentError => error
        raise InputError, "business calendar source is invalid: #{error.message}"
      end

      def date_for(value)
        unless value.is_a?(Time)
          raise InputError, "business calendar date source must be a Time"
        end

        value.getlocal(utc_offset_seconds).strftime("%Y-%m-%d")
      end
    end
  end
end
