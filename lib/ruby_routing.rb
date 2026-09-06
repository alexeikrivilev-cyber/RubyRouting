# frozen_string_literal: true

module RubyRouting
  module ImmutableData
    module_function

    # Copy and recursively freeze generic domain data at a boundary. This is
    # intentionally schema-free: provider adapters may interpret the payload,
    # while the routing core only owns its immutability and identity.
    def deep_freeze(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), copy|
          copy[deep_freeze(key)] = deep_freeze(nested)
        end.freeze
      when Array
        value.map { |nested| deep_freeze(nested) }.freeze
      when String
        value.dup.freeze
      else
        if value.respond_to?(:each)
          RubyRouting::Collection.to_array(value, "immutable nested collection")
            .map { |nested| deep_freeze(nested) }.freeze
        else
          value.freeze
        end
      end
    end
  end

  module Collection
    module_function

    def to_array(value, label)
      unless value.respond_to?(:each)
        raise ArgumentError, "#{label} must be enumerable"
      end

      values = []
      value.each { |item| values << item }
      values
    rescue NoMethodError => error
      raise ArgumentError, "#{label} must support enumeration: #{error.message}"
    end
  end

  module Enum
    module_function

    # Normalize only against a closed set of already-loaded values. In
    # particular, never intern an arbitrary external/durable string with
    # String#to_sym.
    def normalize(value, allowed, label)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "unsupported #{label}"
      end

      match = allowed.find { |candidate| candidate.to_s == value.to_s }
      raise ArgumentError, "unsupported #{label}" unless match

      match
    end
  end

  module Identity
    module_function

    # Routing and durable-state identities are scalar protocol values. Keep
    # this invariant centralized so malformed structured input cannot be
    # coerced into a colliding provider, operation or fact identity.
    def normalize(value, label)
      unless value.is_a?(String) || value.is_a?(Symbol)
        raise ArgumentError, "#{label} must be a non-empty String or Symbol"
      end

      normalized = value.to_s.strip
      raise ArgumentError, "#{label} must be non-empty" if normalized.empty?

      normalized.freeze
    end
  end

  module HashKeys
    module_function

    # Convert only a closed set of known String/Symbol keys. In particular,
    # never call String#to_sym on durable or external input: an unknown key
    # must remain an ordinary validation error rather than an interned symbol.
    def symbolize(value, allowed, label, strict: true)
      unless value.is_a?(Hash)
        raise ArgumentError, "#{label} must be a Hash"
      end

      value.each_with_object({}) do |(key, nested), result|
        unless key.is_a?(String) || key.is_a?(Symbol)
          raise ArgumentError, "#{label} keys must be String or Symbol"
        end

        normalized = allowed.find { |candidate| candidate.to_s == key.to_s }
        if normalized.nil?
          raise ArgumentError, "#{label} contains unsupported key" if strict

          next
        end
        if result.key?(normalized)
          raise ArgumentError, "#{label} contains duplicate key #{normalized}"
        end

        result[normalized] = nested
      end
    end
  end
end

require "digest"

require_relative "ruby_routing/domain/money"
require_relative "ruby_routing/domain/routing_context"
require_relative "ruby_routing/domain/provider_route_capabilities"
require_relative "ruby_routing/domain/payout_intent"
require_relative "ruby_routing/domain/policy_selector"
require_relative "ruby_routing/domain/policy"
require_relative "ruby_routing/domain/policy_resolution"
require_relative "ruby_routing/domain/configuration"
require_relative "ruby_routing/domain/recovery_schedule"
require_relative "ruby_routing/domain/policy_registry"
require_relative "ruby_routing/domain/provider_opportunity"
require_relative "ruby_routing/domain/outcome"
require_relative "ruby_routing/domain/ownership"
require_relative "ruby_routing/domain/decision"
require_relative "ruby_routing/domain/operation"
require_relative "ruby_routing/routing/eligibility"
require_relative "ruby_routing/routing/feasibility"
require_relative "ruby_routing/routing/opportunity_runtime"
require_relative "ruby_routing/routing/allocation"
require_relative "ruby_routing/routing/deviation"
require_relative "ruby_routing/routing/constrained_optimizer"
require_relative "ruby_routing/routing/recovery"
require_relative "ruby_routing/routing/recovery_selection"
require_relative "ruby_routing/routing/health"
require_relative "ruby_routing/routing/quality"
require_relative "ruby_routing/routing/decision_engine"
require_relative "ruby_routing/routing/decision_evaluator"
require_relative "ruby_routing/state/snapshot"
require_relative "ruby_routing/state/provider_execution_failure_evidence"
require_relative "ruby_routing/state/fact_codec"
require_relative "ruby_routing/state/fact_store"
require_relative "ruby_routing/state/clock"
require_relative "ruby_routing/state/admission_ledger"
require_relative "ruby_routing/state/allocation_ledger"
require_relative "ruby_routing/state/lifecycle_ledger"
require_relative "ruby_routing/state/observation_ledger"
require_relative "ruby_routing/state/provider_catalog_ledger"
require_relative "ruby_routing/state/provider_catalog_restorer"
require_relative "ruby_routing/state/admission_fact_restorer"
require_relative "ruby_routing/state/allocation_fact_restorer"
require_relative "ruby_routing/state/lifecycle_fact_restorer"
require_relative "ruby_routing/state/observation_fact_restorer"
require_relative "ruby_routing/state/operation_fact_restorer"
require_relative "ruby_routing/state/provider_evidence_fact_restorer"
require_relative "ruby_routing/state/financial_fact_restorer"
require_relative "ruby_routing/state/payout_fact_restorer"
require_relative "ruby_routing/state/opportunity_evaluation_fact_restorer"
require_relative "ruby_routing/state/decision_trace_validator"
require_relative "ruby_routing/state/decision_fact_restorer"
require_relative "ruby_routing/state/restored_state_validator"
require_relative "ruby_routing/state/operation_committer"
require_relative "ruby_routing/state/working_state_restorer"
require_relative "ruby_routing/state/coordinator"
require_relative "ruby_routing/ports/provider"
require_relative "ruby_routing/application/orchestrator"
require_relative "ruby_routing/application/configuration"
require_relative "ruby_routing/application/commands"
require_relative "ruby_routing/application/queries"
require_relative "ruby_routing/application/service"
require_relative "ruby_routing/application/recovery_executor"
require_relative "ruby_routing/application/http_app"
require_relative "ruby_routing/demo/scripted_provider"
require_relative "ruby_routing/demo/scenario"
require_relative "ruby_routing/projections/analytics"
require_relative "ruby_routing/projections/replay"
require_relative "ruby_routing/projections/public_audit_fact"
require_relative "ruby_routing/projections/explanation"
require_relative "ruby_routing/case"
