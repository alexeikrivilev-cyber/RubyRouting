# frozen_string_literal: true

module RubyRouting
  class RoutingPolicy
    MEASURES = %i[count volume].freeze
    ACCOUNTING_POINTS = %i[primary_assignment].freeze
    WINDOWS = %i[opportunity_cohort].freeze

    attr_reader :id, :epoch, :measure, :targets, :currency, :scope, :accounting_point,
                :window, :max_attempts

    def initialize(id:, epoch:, measure:, targets:, currency: nil, scope: :default,
                   accounting_point: :primary_assignment, window: :opportunity_cohort,
                   max_attempts: 3)
      @id = normalize_id(id, "policy id")
      @epoch = normalize_id(epoch, "policy epoch")
      @measure = normalize_measure(measure)
      @targets = normalize_targets(targets)
      @currency = normalize_currency(currency)
      @scope = normalize_id(scope, "policy scope")
      @accounting_point = normalize_symbol(accounting_point, ACCOUNTING_POINTS, "accounting point")
      @window = normalize_symbol(window, WINDOWS, "window")
      @max_attempts = normalize_max_attempts(max_attempts)

      if @measure == :volume && @currency.nil?
        raise ArgumentError, "volume policies require a currency"
      end

      freeze
    end

    def scope_key
      [id, epoch, scope].freeze
    end

    def weight_for(provider_id)
      targets.fetch(provider_id.to_s, 0)
    end

    def weights_for(provider_ids)
      provider_ids.each_with_object({}) do |provider_id, weights|
        normalized = provider_id.to_s
        weight = weight_for(normalized)
        weights[normalized] = weight if weight.positive?
      end.freeze
    end

    def measure_for(money)
      unless money.is_a?(RubyRouting::Money)
        raise ArgumentError, "measure requires RubyRouting::Money"
      end

      if measure == :count
        1
      else
        unless money.currency == currency
          raise ArgumentError, "policy currency does not match payout currency"
        end
        money.amount_minor
      end
    end

    private

    def normalize_id(value, label)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "#{label} must be a non-empty String or Symbol"
      end

      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end

    def normalize_measure(value)
      normalized = value.to_sym
      raise ArgumentError, "measure must be count or volume" unless MEASURES.include?(normalized)

      normalized
    rescue NoMethodError
      raise ArgumentError, "measure must be count or volume"
    end

    def normalize_targets(value)
      unless value.is_a?(Hash) && !value.empty?
        raise ArgumentError, "targets must be a non-empty Hash"
      end

      normalized = value.each_with_object({}) do |(provider_id, weight), copy|
        id = normalize_id(provider_id, "provider id")
        unless weight.is_a?(Integer) && weight.positive?
          raise ArgumentError, "provider weights must be positive Integers"
        end
        raise ArgumentError, "duplicate provider id" if copy.key?(id)

        copy[id] = weight
      end
      normalized.freeze
    end

    def normalize_currency(value)
      return nil if value.nil?
      unless value.is_a?(String)
        raise ArgumentError, "currency must be a String"
      end

      normalized = value.strip.upcase
      unless /\A[A-Z]{3}\z/.match?(normalized)
        raise ArgumentError, "currency must be a three-letter code"
      end

      normalized.freeze
    end

    def normalize_symbol(value, allowed, label)
      normalized = value.to_sym
      raise ArgumentError, "unsupported #{label}" unless allowed.include?(normalized)

      normalized
    rescue NoMethodError
      raise ArgumentError, "unsupported #{label}"
    end

    def normalize_max_attempts(value)
      unless value.is_a?(Integer) && value.positive?
        raise ArgumentError, "max_attempts must be a positive Integer"
      end

      value
    end
  end
end
