# frozen_string_literal: true

require "digest"

module RubyRouting
  module Case
    class SimulationResult
      attr_reader :status, :latency_sec

      STATUSES = %i[approved rejected expired].freeze

      def initialize(status:, latency_sec:)
        raise InputError, "unsupported simulated status #{status.inspect}" unless STATUSES.include?(status)
        raise InputError, "latency_sec must be a non-negative Integer" unless latency_sec.is_a?(Integer) && latency_sec >= 0
        @status = status
        @latency_sec = latency_sec
        freeze
      end

      def approved?
        status == :approved
      end
    end

    class DeterministicSimulator
      def initialize(seed: "ruby-routing-v0.4", outcomes: {}, mode: :approved)
        @seed = Input.assert_string(seed, "simulation seed").freeze
        unless outcomes.is_a?(Hash)
          raise InputError, "simulation outcomes must be a Hash"
        end
        @outcomes = outcomes.each_with_object({}) do |(key, value), result|
          unless key.is_a?(Array) && key.length == 2 && key.all? { |part| part.is_a?(String) || part.is_a?(Symbol) }
            raise InputError, "simulation outcome keys must be [operation_id, provider_id]"
          end
          canonical_key = key.map.with_index do |part, index|
            Input.assert_id(part, index.zero? ? "simulation outcome operation id" : "simulation outcome provider id")
          end.freeze
          raise InputError, "duplicate simulation outcome key #{canonical_key.inspect}" if result.key?(canonical_key)
          unless value.is_a?(String) || value.is_a?(Symbol)
            raise InputError, "simulation outcome must be a String or Symbol"
          end
          result[canonical_key] = value.to_sym
        end.freeze
        @mode = mode
        raise InputError, "unsupported simulator mode #{@mode.inspect}" unless %i[approved conversion].include?(@mode)
      end

      def call(operation, provider, attempt_index:)
        override = @outcomes[[operation.operation_id, provider.payment_system]]
        return result_from(override, provider) if override
        return SimulationResult.new(status: :approved, latency_sec: provider.avg_latency_sec) if @mode == :approved

        digest = Digest::SHA256.hexdigest([@seed, operation.operation_id, provider.payment_system, attempt_index].join("\0"))
        bucket = digest[0, 8].to_i(16) % 10_000
        conversion_threshold = (provider.conversion_24h * 10_000).to_i
        if bucket < conversion_threshold
          SimulationResult.new(status: :approved, latency_sec: provider.avg_latency_sec)
        elsif bucket.even?
          SimulationResult.new(status: :expired, latency_sec: provider.avg_latency_sec)
        else
          SimulationResult.new(status: :rejected, latency_sec: provider.avg_latency_sec)
        end
      end

      private

      def result_from(value, provider)
        status = value.to_sym
        latency = provider.avg_latency_sec
        SimulationResult.new(status: status, latency_sec: latency)
      end
    end

    class Attempt
      CLASSIFICATIONS = %i[
        hard_skipped attempted_approved attempted_rejected attempted_expired terminal_non_approval
      ].freeze

      attr_reader :provider, :decision, :reason, :status, :latency_sec, :selection, :classification

      def initialize(provider:, decision:, reason:, status: nil, latency_sec: nil, selection: nil,
                     classification: nil)
        raise OutputError, "attempt decision must be selected or skipped" unless %i[selected skipped].include?(decision)
        @provider = Input.assert_id(provider, "attempt provider")
        @decision = decision
        @reason = Input.assert_id(reason, "attempt reason")
        @status = status
        @latency_sec = latency_sec
        @selection = selection
        @classification = classification || default_classification
        unless CLASSIFICATIONS.include?(@classification)
          raise OutputError, "unsupported internal attempt classification #{@classification.inspect}"
        end
        if @classification == :hard_skipped && @status
          raise OutputError, "hard-skipped attempt cannot have an outcome"
        end
        if @classification != :hard_skipped && !@status
          raise OutputError, "invoked attempt must have an outcome"
        end
        freeze
      end

      def to_h
        value = { provider: provider, decision: decision.to_s, reason: reason }
        value[:simulated_result] = status.to_s if status
        value[:latency_sec] = latency_sec unless latency_sec.nil?
        value.freeze
      end

      def hard_skipped?
        classification == :hard_skipped
      end

      def attempted?
        !hard_skipped?
      end

      private

      def default_classification
        return :hard_skipped unless status
        return :attempted_approved if status.to_sym == :approved
        return :attempted_rejected if status.to_sym == :rejected && decision == :selected
        return :attempted_expired if status.to_sym == :expired && decision == :selected

        :terminal_non_approval
      end
    end

    class Decision
      attr_reader :operation_id, :selected_provider, :attempts, :simulated_result, :latency_sec, :selection

      def initialize(operation_id:, selected_provider:, attempts:, simulated_result:, latency_sec:, selection: nil)
        @operation_id = Input.assert_id(operation_id, "decision operation_id")
        @selected_provider = Input.assert_id(selected_provider, "decision selected_provider")
        @attempts = attempts.freeze
        @simulated_result = Input.assert_id(simulated_result, "decision simulated_result")
        @latency_sec = latency_sec
        @selection = selection
        freeze
      end

      def to_h
        {
          operation_id: operation_id,
          selected_provider: selected_provider,
          attempts: attempts.map(&:to_h),
          simulated_result: simulated_result,
          latency_sec: latency_sec
        }.freeze
      end
    end

    class Router
      attr_reader :dataset, :state, :traffic, :attempt_ledger, :settlement_ledger,
                  :configuration, :profile, :simulator, :resolver

      def initialize(dataset, simulator: nil, terminal_provider_id: nil,
                     rpm_limits: {}, traffic_targets: nil, resolver: nil, configuration: nil,
                     profile: nil)
        @dataset = dataset
        provider_ids = dataset.providers.map(&:payment_system)
        if !profile.nil? && !configuration.nil?
          raise InputError, "case router accepts either profile or configuration, not both"
        end
        unless resolver.nil? || resolver.is_a?(ConflictResolver)
          raise InputError, "case router resolver must be ConflictResolver"
        end
        policy_override = !terminal_provider_id.nil? || !traffic_targets.nil? ||
          !rpm_limits.is_a?(Hash) || !rpm_limits.empty? || !resolver.nil?
        if (!profile.nil? || !configuration.nil?) && policy_override
          raise InputError, "case router policy source cannot be combined with policy overrides"
        end
        config = if !profile.nil?
          unless profile.is_a?(SubmissionProfile)
            raise InputError, "case router profile must be SubmissionProfile"
          end
          profile.configuration
        elsif !configuration.nil?
          CaseConfiguration.from(configuration, provider_ids: provider_ids)
        else
          CaseConfiguration.new(
            provider_ids: provider_ids,
            terminal_provider_id: terminal_provider_id,
            rpm_limits: rpm_limits,
            targets: traffic_targets,
            weights: resolver ? resolver.weights : RoutingWeights.new
          )
        end
        unless config.provider_ids == provider_ids.sort
          raise InputError, "case configuration provider ids do not match dataset"
        end
        @configuration = config
        @profile = profile
        @state = CaseState.new(
          dataset,
          rpm_limits: config.rpm_limits,
          rpm_window_seconds: config.rpm_window_seconds
        )
        @traffic = TrafficLedger.new(
          dataset.providers.map(&:payment_system),
          targets: config.targets
        )
        @attempt_ledger = AttemptLedger.new(dataset.providers.map(&:payment_system))
        @settlement_ledger = SettlementLedger.new(dataset.providers.map(&:payment_system))
        @simulator = simulator || DeterministicSimulator.new(
          seed: config.simulation_seed, mode: config.simulation_mode
        )
        @resolver = resolver || ConflictResolver.new(
          weights: config.weights, min_turnovers: config.min_turnovers,
          preferred_amount_ranges: config.preferred_amount_ranges
        )
        @terminal_provider_id = config.terminal_provider_id || dataset.providers.find(&:self_provider?)&.payment_system
        unless @terminal_provider_id
          raise InputError, "dataset has no configured terminal self-provider"
        end
        terminal = dataset.providers.find { |provider| provider.payment_system == @terminal_provider_id }
        unless terminal&.active? && terminal.self_provider?
          raise InputError, "terminal provider must be an active zero-participation provider"
        end
        @providers = dataset.providers.sort_by { |provider| [provider.priority, provider.payment_system] }
        @hard_constraints = HardConstraintEvaluator.new
      end

      def run
        dataset.operations.map { |operation| route(operation) }.freeze
      end

      def route(operation)
        as_of = operation.created_at
        attempts = []
        candidates = @providers.reject { |provider| provider.payment_system == @terminal_provider_id }
        attempt_index = 0
        assignment_recorded = false
        loop do
          eligible_states = []
          candidates.each do |provider|
            provider_state = state.fetch(provider.payment_system)
            eligibility = @hard_constraints.call(provider_state, operation, as_of: as_of)
            if eligibility.eligible?
              eligible_states << provider_state
            else
              attempts << Attempt.new(provider: provider.payment_system, decision: :skipped, reason: eligibility.reason)
            end
          end
          # A hard exclusion is a fact for this operation, not a new attempt
          # on every fallback pass. Keep only eligible providers for the next
          # resolver/simulation pass so attempt history remains unique.
          candidates = eligible_states.map(&:provider)
          break if eligible_states.empty?

          resolution = @resolver.resolve(
            candidates: eligible_states, operation: operation, traffic: traffic, as_of: as_of
          )
          provider = eligible_states.find { |item| item.provider.payment_system == resolution.selected_provider }.provider
          provider_state = state.fetch(provider.payment_system)
          unless assignment_recorded
            traffic.record_assignment!(provider_id: provider.payment_system, amount: operation.amount)
            assignment_recorded = true
          end
          provider_state.reserve!(operation, as_of: as_of)
          simulation = @simulator.call(operation, provider, attempt_index: attempt_index)
          provider_state.release!(operation)
          provider_state.record_outcome!(operation, simulation.status)
          attempt_ledger.record!(provider_id: provider.payment_system, amount: operation.amount, status: simulation.status)
          attempt_index += 1
          if simulation.approved?
            provider_state.record_route!(operation)
            settlement_ledger.record!(provider_id: provider.payment_system, amount: operation.amount)
            attempts << Attempt.new(
              provider: provider.payment_system, decision: :selected, reason: "selected",
              status: simulation.status, latency_sec: simulation.latency_sec,
              selection: resolution.to_h, classification: :attempted_approved
            )
            return Decision.new(
              operation_id: operation.operation_id,
              selected_provider: provider.payment_system,
              attempts: attempts,
              simulated_result: simulation.status,
              latency_sec: simulation.latency_sec,
              selection: resolution.to_h
            )
          end

          attempts << Attempt.new(
            provider: provider.payment_system, decision: :selected,
            reason: simulation.status == :expired ? "provider_expired" : "provider_rejected",
            status: simulation.status, latency_sec: simulation.latency_sec,
            selection: resolution.to_h,
            classification: simulation.status == :expired ? :attempted_expired : :attempted_rejected
          )
          candidates = candidates.reject { |candidate| candidate.payment_system == provider.payment_system }
        end

        terminal = state.fetch(@terminal_provider_id)
        terminal_eligibility = @hard_constraints.call(terminal, operation, as_of: as_of, terminal: true)
        unless terminal_eligibility.eligible?
          raise OutputError, "terminal self-provider #{@terminal_provider_id} is ineligible: #{terminal_eligibility.reason}"
        end
        terminal_reason = attempts.empty? ? "terminal_fallback" : "external_providers_exhausted"
        unless assignment_recorded
          traffic.record_assignment!(provider_id: @terminal_provider_id, amount: operation.amount)
          assignment_recorded = true
        end
        terminal.reserve!(operation, as_of: as_of)
        simulation = @simulator.call(operation, terminal.provider, attempt_index: attempt_index)
        terminal.release!(operation)
        terminal.record_outcome!(operation, simulation.status)
        attempt_ledger.record!(provider_id: @terminal_provider_id, amount: operation.amount, status: simulation.status)
        terminal.record_route!(operation) if simulation.approved?
        settlement_ledger.record!(provider_id: @terminal_provider_id, amount: operation.amount) if simulation.approved?
        attempts << Attempt.new(
          provider: @terminal_provider_id, decision: :selected, reason: terminal_reason,
          status: simulation.status, latency_sec: simulation.latency_sec,
          classification: simulation.approved? ? :attempted_approved : :terminal_non_approval
        )
        Decision.new(
          operation_id: operation.operation_id,
          selected_provider: @terminal_provider_id,
          attempts: attempts,
          simulated_result: simulation.status,
          latency_sec: simulation.latency_sec,
          selection: nil
        )
      end
    end
  end
end
