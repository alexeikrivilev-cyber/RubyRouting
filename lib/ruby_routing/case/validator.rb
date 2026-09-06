# frozen_string_literal: true

module RubyRouting
  module Case
    class ValidationResult
      attr_reader :errors, :warnings

      def initialize(errors:, warnings: [])
        @errors = errors.map(&:to_s).freeze
        @warnings = warnings.map(&:to_s).freeze
        freeze
      end

      def valid?
        errors.empty?
      end
    end

    # Internal validation is intentionally stricter than the organizer's
    # public compatibility script. It validates the actual in-memory run so
    # serialized projections cannot hide state or accounting inconsistencies.
    class StrictValidator
      def initialize(run)
        @run = run
        @dataset = run.dataset
        @operations_by_id = @dataset.operations.to_h { |operation| [operation.operation_id, operation] }
        @decisions_by_id = @run.decisions.to_h { |decision| [decision.operation_id, decision] }
        @errors = []
      end

      def call
        validate_decision_coverage
        validate_decisions
        validate_stateful_replay
        validate_state_conservation
        validate_traffic_conservation
        validate_attempt_accounting
        validate_settlement_accounting
        validate_report_projection
        validate_recommendations
        ValidationResult.new(errors: @errors)
      end

      def validate!
        result = call
        return result if result.valid?

        raise OutputError, "strict case validation failed: #{result.errors.join('; ')}"
      end

      private

      def validate_decision_coverage
        expected = @dataset.operations.map(&:operation_id)
        actual = @run.decisions.map(&:operation_id)
        add("decision count #{actual.length} does not equal queue count #{expected.length}") unless actual.length == expected.length
        add("duplicate decision operation_id") unless actual.uniq.length == actual.length
        add("decision coverage differs from queue") unless actual.sort == expected.sort
      end

      def validate_decisions
        known = @dataset.providers.map(&:payment_system)
        terminal = @run.configuration.terminal_provider_id || @dataset.providers.find(&:self_provider?)&.payment_system
        @run.decisions.each do |decision|
          operation = @operations_by_id[decision.operation_id]
          unless operation
            add("#{decision.operation_id}: unknown operation")
            next
          end
          attempts = decision.attempts
          add("#{decision.operation_id}: attempts must not be empty") if attempts.empty?
          add("#{decision.operation_id}: selected provider is unknown") unless known.include?(decision.selected_provider)
          selected = attempts.select { |attempt| attempt.decision == :selected }
          add("#{decision.operation_id}: must have a selected attempt") if selected.empty?
          if selected.any?
            final_selected = selected.last
            add("#{decision.operation_id}: selected_provider disagrees with final attempt") unless final_selected.provider == decision.selected_provider
            add("#{decision.operation_id}: selected attempt must be last") unless attempts.last.equal?(final_selected)
            selected.each do |attempt|
              valid_selected_status = %i[approved rejected expired].include?(attempt.status)
              add("#{decision.operation_id}: selected attempt has invalid simulation status") unless valid_selected_status
              add("#{decision.operation_id}: selected attempt must be classified as invoked") unless attempt.attempted?
              if attempt != final_selected && attempt.status == :approved
                add("#{decision.operation_id}: an approved attempt cannot precede the final attempt")
              end
            end
            if final_selected.status != :approved && final_selected.provider != terminal
              add("#{decision.operation_id}: only terminal provider may be a non-approved final attempt")
            end
            add("#{decision.operation_id}: decision selection trace disagrees with final attempt") unless decision.selection == final_selected.selection
          end
          seen = []
          attempts.each do |attempt|
            add("#{decision.operation_id}: unknown attempt provider #{attempt.provider}") unless known.include?(attempt.provider)
            add("#{decision.operation_id}: duplicate attempt provider #{attempt.provider}") if seen.include?(attempt.provider)
            seen << attempt.provider
            if attempt.hard_skipped?
              add("#{decision.operation_id}: hard-skipped attempt must use skipped decision") unless attempt.decision == :skipped
              valid_reason = %w[provider_rejected provider_expired] + HardReasonCodes::ALL
              add("#{decision.operation_id}: invalid skipped reason #{attempt.reason}") unless valid_reason.include?(attempt.reason)
              add("#{decision.operation_id}: hard-skipped attempt must not have latency") unless attempt.latency_sec.nil?
              add("#{decision.operation_id}: hard-skipped attempt must not have selection") unless attempt.selection.nil?
            elsif attempt.decision != :selected
              add("#{decision.operation_id}: invoked attempt must use selected decision")
            elsif !%i[approved rejected expired].include?(attempt.status)
              add("#{decision.operation_id}: invoked attempt has invalid simulation status")
            elsif !attempt.latency_sec.is_a?(Integer) || attempt.latency_sec.negative?
              add("#{decision.operation_id}: invoked attempt latency must be a non-negative Integer")
            end
          end
          if decision.selected_provider == terminal
            add("#{decision.operation_id}: terminal provider must be the final selected attempt") unless attempts.last&.provider == terminal
          end
          add("#{decision.operation_id}: top-level result disagrees with final attempt") unless decision.simulated_result == attempts.last&.status.to_s
          add("#{decision.operation_id}: latency must be a non-negative Integer") unless decision.latency_sec.is_a?(Integer) && decision.latency_sec >= 0
          add("#{decision.operation_id}: operation amount must be positive") unless operation.amount.positive?
        end
      end

      def validate_state_conservation
        @dataset.providers.each do |provider|
          state = @run.state.fetch(provider.payment_system)
          expected_approved = @dataset.operations.sum do |operation|
            decision = @decisions_by_id[operation.operation_id]
            decision&.selected_provider == provider.payment_system && decision.simulated_result == "approved" ? operation.amount : 0
          end
          expected_routes = @run.decisions.count do |decision|
            decision.selected_provider == provider.payment_system && decision.simulated_result == "approved"
          end
          expected_routed_volume = @run.decisions.sum do |decision|
            next 0 unless decision.selected_provider == provider.payment_system && decision.simulated_result == "approved"
            operation = operation_for(decision)
            next 0 unless operation

            operation.amount
          end
          add("#{provider.payment_system}: daily approved conservation failed") unless state.daily_approved_amount == provider.daily_approved_amount + expected_approved
          add("#{provider.payment_system}: transient exposure must be zero") unless state.transient_count.zero? && state.transient_amount.zero?
          add("#{provider.payment_system}: routed count conservation failed") unless state.routed_count == expected_routes
          add("#{provider.payment_system}: routed volume conservation failed") unless state.routed_volume == expected_routed_volume
        end
      end

      def validate_stateful_replay
        replay_state = CaseState.new(
          @dataset,
          rpm_limits: @run.configuration.rpm_limits,
          rpm_window_seconds: @run.configuration.rpm_window_seconds
        )
        replay_traffic = TrafficLedger.new(
          @dataset.providers.map(&:payment_system), targets: @run.configuration.targets
        )
        terminal_id = @run.configuration.terminal_provider_id || @dataset.providers.find(&:self_provider?)&.payment_system
        ordered_external = @dataset.providers
          .reject { |provider| provider.payment_system == terminal_id }
          .sort_by { |provider| [provider.priority, provider.payment_system] }
        hard = HardConstraintEvaluator.new

        @dataset.operations.each do |operation|
          decision = @decisions_by_id[operation.operation_id]
          next unless decision
          remaining = ordered_external.dup
          cursor = 0
          attempt_index = 0
          assignment_recorded = false
          loop do
            eligible = []
            remaining.dup.each do |provider|
              result = hard.call(replay_state.fetch(provider.payment_system), operation, as_of: operation.created_at)
              if result.eligible?
                eligible << replay_state.fetch(provider.payment_system)
              else
                actual = decision.attempts[cursor]
                add("#{operation.operation_id}: hard replay missing #{provider.payment_system}") unless actual&.provider == provider.payment_system && actual.decision == :skipped && actual.status.nil? && actual.reason == result.reason.to_s
                cursor += 1 if actual&.provider == provider.payment_system
                remaining.delete(provider)
              end
            end
            break if eligible.empty?

            resolution = @run.resolver.resolve(
              candidates: eligible, operation: operation, traffic: replay_traffic,
              as_of: operation.created_at
            )
            actual = decision.attempts[cursor]
            add("#{operation.operation_id}: resolver replay selected #{resolution.selected_provider}, output selected #{actual&.provider}") unless actual&.provider == resolution.selected_provider
            add("#{operation.operation_id}: resolver trace differs from output") unless actual&.selection == resolution.to_h
            simulation = @run.simulator.call(
              operation, replay_state.fetch(resolution.selected_provider).provider, attempt_index: attempt_index
            )
            unless assignment_recorded
              replay_traffic.record_assignment!(
                provider_id: resolution.selected_provider, amount: operation.amount
              )
              assignment_recorded = true
            end
            add("#{operation.operation_id}: simulator replay differs for #{resolution.selected_provider}") unless actual&.status == simulation.status && actual.latency_sec == simulation.latency_sec
            expected_reason = simulation.approved? ? "selected" : (simulation.status == :expired ? "provider_expired" : "provider_rejected")
            add("#{operation.operation_id}: outcome reason differs for #{resolution.selected_provider}") unless actual&.reason == expected_reason
            replay_provider = replay_state.fetch(resolution.selected_provider)
            replay_provider.reserve!(operation, as_of: operation.created_at)
            replay_provider.release!(operation)
            replay_provider.record_outcome!(operation, simulation.status)
            attempt_index += 1
            cursor += 1 if actual&.provider == resolution.selected_provider
            if simulation.approved?
              replay_provider.record_route!(operation)
              break
            end
            add("#{operation.operation_id}: failed provider must be an invoked selected attempt") unless actual&.decision == :selected && actual.attempted?
            remaining.delete_if { |provider| provider.payment_system == resolution.selected_provider }
          end

          if cursor < decision.attempts.length && decision.attempts[cursor].provider == terminal_id
            terminal = replay_state.fetch(terminal_id)
            actual = decision.attempts[cursor]
            terminal_eligibility = hard.call(terminal, operation, as_of: operation.created_at, terminal: true)
            unless terminal_eligibility.eligible?
              add("#{operation.operation_id}: terminal provider is ineligible: #{terminal_eligibility.reason}")
            else
              simulation = @run.simulator.call(operation, terminal.provider, attempt_index: attempt_index)
              add("#{operation.operation_id}: terminal simulator replay differs") unless actual.status == simulation.status && actual.latency_sec == simulation.latency_sec
              expected_reason = decision.attempts.length == 1 ? "terminal_fallback" : "external_providers_exhausted"
              add("#{operation.operation_id}: terminal reason differs") unless actual.reason == expected_reason
              unless assignment_recorded
                replay_traffic.record_assignment!(provider_id: terminal_id, amount: operation.amount)
                assignment_recorded = true
              end
              terminal.reserve!(operation, as_of: operation.created_at)
              terminal.release!(operation)
              terminal.record_outcome!(operation, simulation.status)
              if simulation.approved?
                terminal.record_route!(operation)
              end
            end
            cursor += 1
          end
          add("#{operation.operation_id}: stateful replay left unconsumed attempts") unless cursor == decision.attempts.length
        end
      rescue StandardError => error
        add("stateful replay failed: #{error.class}: #{error.message}")
      end

      def validate_traffic_conservation
        expected_count = @run.decisions.each_with_object(Hash.new(0)) do |decision, counts|
          provider = primary_provider(decision)
          counts[provider] += 1 if provider
        end
        expected_volume = @run.decisions.each_with_object(Hash.new(0)) do |decision, volumes|
          provider = primary_provider(decision)
          next unless provider
          operation = operation_for(decision)
          volumes[provider] += operation.amount if operation
        end
        @run.traffic.provider_ids.each do |provider_id|
          add("#{provider_id}: traffic count differs from decisions") unless @run.traffic.count_by_provider.fetch(provider_id) == expected_count[provider_id]
          add("#{provider_id}: traffic volume differs from decisions") unless @run.traffic.volume_by_provider.fetch(provider_id) == expected_volume[provider_id]
        end
        assigned_count = @run.decisions.count { |decision| primary_provider(decision) }
        assigned_volume = @run.decisions.sum do |decision|
          primary_provider(decision) ? (operation_for(decision)&.amount || 0) : 0
        end
        add("assignment traffic total count differs from primary assignments") unless @run.traffic.total_count == assigned_count
        add("assignment traffic total volume differs from primary assignments") unless @run.traffic.total_volume == assigned_volume
      end

      def validate_attempt_accounting
        ledger = @run.attempt_ledger
        add("attempt ledger is missing") and return unless ledger.is_a?(AttemptLedger)
        expected = Hash.new { |hash, key| hash[key] = { count: 0, volume: 0, outcomes: Hash.new(0) } }
        @run.decisions.each do |decision|
          operation = operation_for(decision)
          next unless operation
          decision.attempts.each do |attempt|
            next unless attempt.status

            entry = expected[attempt.provider]
            entry[:count] += 1
            entry[:volume] += operation.amount
            entry[:outcomes][attempt.status] += 1
          end
        end
        ledger.provider_ids.each do |provider_id|
          expected_entry = expected[provider_id]
          add("#{provider_id}: attempt count differs from decisions") unless ledger.count_by_provider.fetch(provider_id) == expected_entry[:count]
          add("#{provider_id}: attempt volume differs from decisions") unless ledger.volume_by_provider.fetch(provider_id) == expected_entry[:volume]
        end
        expected_outcomes = %i[approved rejected expired].to_h { |status| [status, expected.values.sum { |entry| entry[:outcomes][status] }] }
        add("attempt outcome counts differ from decisions") unless ledger.by_outcome == expected_outcomes
      end

      def validate_settlement_accounting
        ledger = @run.settlement_ledger
        add("settlement ledger is missing") and return unless ledger.is_a?(SettlementLedger)
        expected_count = Hash.new(0)
        expected_volume = Hash.new(0)
        @run.decisions.each do |decision|
          next unless decision.simulated_result == "approved"

          operation = operation_for(decision)
          next unless operation
          expected_count[decision.selected_provider] += 1
          expected_volume[decision.selected_provider] += operation.amount
        end
        ledger.provider_ids.each do |provider_id|
          add("#{provider_id}: settlement count differs from decisions") unless ledger.count_by_provider.fetch(provider_id) == expected_count[provider_id]
          add("#{provider_id}: settlement volume differs from decisions") unless ledger.volume_by_provider.fetch(provider_id) == expected_volume[provider_id]
        end
        add("settlement total count differs from decisions") unless ledger.total_count == expected_count.values.sum
        add("settlement total volume differs from decisions") unless ledger.total_volume == expected_volume.values.sum
      end

      def validate_report_projection
        expected = ReportBuilder.new(
          @dataset, @run.state, @run.traffic, @run.configuration, @run.decisions,
          profile: @run.profile, attempt_ledger: @run.attempt_ledger,
          settlement_ledger: @run.settlement_ledger
        ).call.to_h
        add("report is not recomputable from the run") unless expected == @run.report.to_h
      rescue StandardError => error
        add("report projection failed: #{error.class}: #{error.message}")
      end

      def validate_recommendations
        recommendations = @run.report.to_h[:recommendations]
        add("report recommendations must be an Array") unless recommendations.is_a?(Array)
        return unless recommendations.is_a?(Array)

        known = @dataset.providers.map(&:payment_system)
        recommendations.each do |recommendation|
          unless recommendation.is_a?(Hash) && known.include?(recommendation[:provider])
            add("report recommendation references an unknown provider")
            next
          end
          add("report recommendation has no actionable kind") unless recommendation[:kind].is_a?(String) && !recommendation[:kind].empty?
          add("report recommendation has no action") unless recommendation[:action].is_a?(String) && !recommendation[:action].empty?
          add("report recommendation has no evidence") unless recommendation[:evidence].is_a?(Hash) && !recommendation[:evidence].empty?
        end
      end

      def add(message)
        @errors << message
      end

      def operation_for(decision)
        @operations_by_id[decision.operation_id]
      end

      def primary_provider(decision)
        decision.attempts.find { |attempt| attempt.status }&.provider
      end
    end

    # Validates the artifacts that actually crossed the JSON boundary. The
    # in-memory StrictValidator cannot detect serializer shape drift or a
    # write-path that emits a different DTO than the one it validated.
    class SerializedArtifactValidator
      DECISION_KEYS = %w[operation_id selected_provider attempts simulated_result latency_sec].freeze
      ATTEMPT_KEYS = %w[provider decision reason simulated_result latency_sec].freeze
      STATUSES = %w[approved rejected expired].freeze

      def initialize(run, decisions_path:, report_path:)
        @run = run
        @decisions_path = decisions_path
        @report_path = report_path
        @errors = []
      end

      def call
        decisions = parse(@decisions_path, "decisions")
        report = parse(@report_path, "report")
        validate_decisions(decisions)
        validate_report(report)
        ValidationResult.new(errors: @errors)
      end

      def validate!
        result = call
        return result if result.valid?

        raise OutputError, "serialized case validation failed: #{result.errors.join('; ')}"
      end

      private

      def parse(path, label)
        JSON.parse(File.read(path), create_additions: false)
      rescue Errno::ENOENT => error
        add("#{label} artifact not found: #{error.message}")
        nil
      rescue JSON::ParserError => error
        add("#{label} artifact is invalid JSON: #{error.message}")
        nil
      rescue SystemCallError => error
        add("#{label} artifact cannot be read: #{error.message}")
        nil
      end

      def validate_decisions(value)
        unless value.is_a?(Array)
          add("decisions artifact must be an Array")
          return
        end
        expected = @run.decisions.map(&:to_h)
        expected = JSON.parse(JSON.generate(Serializer.json_value(expected)), create_additions: false)
        add("decisions artifact differs from the validated run") unless value == expected
        add("decisions artifact has wrong operation count") unless value.length == @run.dataset.operations.length

        ids = value.map { |decision| decision.is_a?(Hash) ? decision["operation_id"] : nil }
        compact_ids = ids.compact
        add("decisions artifact operation ids must be Strings") unless compact_ids.all? { |id| id.is_a?(String) }
        add("decisions artifact has duplicate operation ids") unless compact_ids.uniq.length == compact_ids.length
        if compact_ids.all? { |id| id.is_a?(String) }
          add("decisions artifact coverage differs from queue") unless compact_ids.sort == @run.dataset.operations.map(&:operation_id).sort
        else
          add("decisions artifact coverage cannot be checked with malformed operation ids")
        end
        value.each_with_index { |decision, index| validate_decision(decision, index) }
      end

      def validate_decision(decision, index)
        unless decision.is_a?(Hash)
          add("decisions[#{index}] must be an object")
          return
        end
        unexpected = decision.keys - DECISION_KEYS
        add("decisions[#{index}] contains unsupported fields: #{unexpected.join(', ')}") unless unexpected.empty?
        DECISION_KEYS.each { |key| add("decisions[#{index}] missing #{key}") unless decision.key?(key) }
        add("decisions[#{index}] operation_id must be a String") unless decision["operation_id"].is_a?(String)
        add("decisions[#{index}] selected_provider must be a String") unless decision["selected_provider"].is_a?(String)
        add("decisions[#{index}] simulated_result is invalid") unless STATUSES.include?(decision["simulated_result"])
        add("decisions[#{index}] latency_sec must be a non-negative Integer") unless decision["latency_sec"].is_a?(Integer) && decision["latency_sec"] >= 0
        attempts = decision["attempts"]
        unless attempts.is_a?(Array) && !attempts.empty?
          add("decisions[#{index}] attempts must be a non-empty Array")
          return
        end
        attempts.each_with_index { |attempt, attempt_index| validate_attempt(attempt, index, attempt_index) }
        selected = attempts.select { |attempt| attempt.is_a?(Hash) && attempt["decision"] == "selected" }
        add("decisions[#{index}] must contain an invoked selected attempt") if selected.empty?
        if selected.any?
          final = selected.last
          add("decisions[#{index}] final attempt must be selected") unless attempts.last.equal?(final)
          add("decisions[#{index}] selected_provider disagrees with final attempt") unless final["provider"] == decision["selected_provider"]
          add("decisions[#{index}] simulated_result disagrees with final attempt") unless final["simulated_result"] == decision["simulated_result"]
        end
      end

      def validate_attempt(attempt, decision_index, attempt_index)
        prefix = "decisions[#{decision_index}].attempts[#{attempt_index}]"
        unless attempt.is_a?(Hash)
          add("#{prefix} must be an object")
          return
        end
        unexpected = attempt.keys - ATTEMPT_KEYS
        add("#{prefix} contains unsupported fields: #{unexpected.join(', ')}") unless unexpected.empty?
        %w[provider decision reason].each { |key| add("#{prefix} missing #{key}") unless attempt.key?(key) }
        add("#{prefix} provider must be a String") unless attempt["provider"].is_a?(String)
        add("#{prefix} decision must be selected or skipped") unless %w[selected skipped].include?(attempt["decision"])
        add("#{prefix} reason must be a String") unless attempt["reason"].is_a?(String)
        if attempt["decision"] == "skipped"
          add("#{prefix} hard skip must not carry simulated_result") if attempt.key?("simulated_result")
          add("#{prefix} hard skip must not carry latency_sec") if attempt.key?("latency_sec")
        else
          add("#{prefix} selected attempt must carry a valid simulated_result") unless STATUSES.include?(attempt["simulated_result"])
          add("#{prefix} selected attempt latency must be a non-negative Integer") unless attempt["latency_sec"].is_a?(Integer) && attempt["latency_sec"] >= 0
        end
      end

      def validate_report(value)
        unless value.is_a?(Hash)
          add("report artifact must be an Object")
          return
        end
        expected = JSON.parse(JSON.generate(Serializer.json_value(@run.report.to_h)), create_additions: false)
        add("report artifact differs from the validated run") unless value == expected
        add("report artifact total_operations differs from queue") unless value["total_operations"] == @run.dataset.operations.length
        add("report artifact lacks assignment_distribution") unless value["assignment_distribution"].is_a?(Hash)
        add("report artifact lacks settlement_distribution") unless value["settlement_distribution"].is_a?(Hash)
        add("report artifact lacks attempt_distribution") unless value["attempt_distribution"].is_a?(Hash)
        profile = value["submission_profile"]
        if @run.profile
          add("report artifact lacks submission profile provenance") unless profile.is_a?(Hash) && profile["profile_id"].is_a?(String)
        end
      end

      def add(message)
        @errors << message
      end
    end

    InternalValidator = StrictValidator

    module HardReasonCodes
      ALL = %w[
        inactive_provider zero_participation amount_below_minimum amount_exceeds_limit
        daily_amount_limit in_progress_count_limit in_progress_amount_limit
        bank_excluded bank_not_in_list negative_margin_without_agreement
        no_available_requisite rpm_limit
      ].freeze
    end
  end
end
