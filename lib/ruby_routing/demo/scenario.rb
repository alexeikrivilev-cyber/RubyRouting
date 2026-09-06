# frozen_string_literal: true

require "json"

module RubyRouting
  module Demo
    module Scenario
      module_function

      CASE_STRATEGY_AMOUNTS_MINOR = [900, 100, 100, 100].freeze

      def run(configuration: nil, providers: nil, intent: nil)
        if configuration.nil?
          default_provider_map_supplied = !providers.nil?
          policy = RubyRouting::RoutingPolicy.new(
            id: "demo-policy",
            epoch: "1",
            measure: :count,
            targets: { "simulated-primary" => 1, "simulated-recovery" => 1 }
          )
          primary = RubyRouting::Demo::ScriptedProvider.new(
            provider_id: "simulated-primary",
            outcomes: [RubyRouting::NormalizedOutcome.safe_route_failure]
          )
          recovery = RubyRouting::Demo::ScriptedProvider.new(
            provider_id: "simulated-recovery",
            outcomes: [RubyRouting::NormalizedOutcome.success(attribution: :provider)]
          )
          default_providers = {
            primary.provider_id => primary,
            recovery.provider_id => recovery
          }
          providers ||= default_providers
          provider_view = default_provider_map_supplied ? providers : { primary: primary, recovery: recovery }
          configuration = RubyRouting::Application::RoutingConfiguration.new(
            policies: [policy],
            provider_opportunities: [
              RubyRouting::ProviderOpportunity.new(provider_id: primary.provider_id),
              RubyRouting::ProviderOpportunity.new(provider_id: recovery.provider_id)
            ]
          )
        elsif !configuration.is_a?(RubyRouting::Application::RoutingConfiguration)
          raise ArgumentError, "configuration must be Application::RoutingConfiguration"
        elsif providers.nil?
          raise ArgumentError, "providers are required for a custom demo configuration"
        end
        intent ||= RubyRouting::PayoutIntent.new(
          id: "demo-payout-1",
          money: RubyRouting::Money.new(100, "RUB"),
          context: { labels: ["demo"], payment_method: "card" }
        )
        unless intent.is_a?(RubyRouting::PayoutIntent)
          raise ArgumentError, "intent must be PayoutIntent"
        end

        coordinator = RubyRouting::State::Coordinator.new
        service = RubyRouting::Application::Service.new(
          coordinator: coordinator,
          providers: providers
        )
        service.apply_configuration(configuration)
        result = service.submit(intent: intent)

        {
          result: result,
          service: service,
          configuration: configuration,
          providers: provider_view || providers
        }.freeze
      end

      # Run the compact judge-facing case through the same typed configuration,
      # Service, RecoveryExecutor and Queries used by the product. This method
      # only assembles evidence; provider choice, allocation, recovery legality
      # and analytics remain owned by the canonical application path.
      def case_run
        source_configuration = case_configuration
        configuration = RubyRouting::Application::RoutingConfiguration.decode(
          JSON.parse(JSON.generate(source_configuration.to_h))
        )
        strategy_runs = {
          count: case_strategy_run(configuration, scope: "count"),
          volume: case_strategy_run(configuration, scope: "volume")
        }.freeze
        recovery_run = case_recovery_run(configuration)
        count_run = strategy_runs.fetch(:count)
        volume_run = strategy_runs.fetch(:volume)
        recovery_service = recovery_run.fetch(:service)
        recovery_providers = recovery_run.fetch(:providers)
        count_analytics = count_run.fetch(:analytics)
        volume_analytics = volume_run.fetch(:analytics)
        recovery_analytics = recovery_run.fetch(:analytics)

        report = {
          configuration: {
            revision: recovery_service.queries.configuration_revision,
            source: "RoutingConfiguration.decode -> Service#apply_configuration",
            policy_ids: configuration.policies.map(&:id).sort,
            provider_ids: configuration.provider_opportunities.map(&:provider_id).sort
          }.freeze,
          strategies: {
            count: strategy_report(count_analytics, "demo-count", CASE_STRATEGY_AMOUNTS_MINOR),
            volume: strategy_report(volume_analytics, "demo-volume", CASE_STRATEGY_AMOUNTS_MINOR)
          }.freeze,
          payouts: [
            *count_run.fetch(:results),
            *volume_run.fetch(:results),
            recovery_run.fetch(:fallback_result),
            recovery_run.fetch(:unknown_result)
          ].to_h do |result|
            payout_id = result.payout.id
            snapshot = if count_run.fetch(:results).include?(result)
              count_run.fetch(:service).queries.payout(payout_id)
            elsif volume_run.fetch(:results).include?(result)
              volume_run.fetch(:service).queries.payout(payout_id)
            else
              recovery_service.queries.payout(payout_id)
            end
            [payout_id, payout_report(
              snapshot,
              status_before_recovery: payout_id == "demo-unknown" ?
                recovery_run.fetch(:unknown_status_before_recovery) : nil
            )]
          end.freeze,
          recovery: recovery_report(recovery_run.fetch(:recovery)),
          analytics: {
            strategies: {
              count: analytics_report(count_analytics),
              volume: analytics_report(volume_analytics)
            }.freeze,
            recovery: analytics_report(recovery_analytics)
          }.freeze,
          provider_calls: provider_calls_for(recovery_providers),
          strategy_provider_calls: {
            count: provider_calls_for(count_run.fetch(:providers)),
            volume: provider_calls_for(volume_run.fetch(:providers))
          }.freeze
        }.freeze

        {
          result: recovery_service.queries.payout("demo-unknown"),
          service: recovery_service,
          configuration: configuration,
          providers: recovery_providers,
          strategy_runs: strategy_runs,
          recovery_run: recovery_run,
          report: report
        }.freeze
      end

      def case_strategy_run(configuration, scope:)
        providers = strategy_providers
        service = RubyRouting::Application::Service.new(
          coordinator: RubyRouting::State::Coordinator.new,
          providers: providers
        )
        service.apply_configuration(configuration)
        results = CASE_STRATEGY_AMOUNTS_MINOR.each_with_index.map do |amount_minor, index|
          case_submit(service, id: "demo-#{scope}-#{index + 1}", scope: scope, amount_minor: amount_minor)
        end.freeze

        {
          service: service,
          providers: providers,
          results: results,
          analytics: service.queries.analytics
        }.freeze
      end

      def case_recovery_run(configuration)
        providers = case_providers
        service = RubyRouting::Application::Service.new(
          coordinator: RubyRouting::State::Coordinator.new,
          providers: providers
        )
        service.apply_configuration(configuration)
        fallback_result = case_submit(service, id: "demo-fallback", scope: "count", amount_minor: 900)
        unknown_result = case_submit(service, id: "demo-unknown", scope: "unknown", amount_minor: 1)
        unknown_status_before_recovery = unknown_result.status
        recovery = service.recovery_executor.run(limit: 1)

        {
          service: service,
          providers: providers,
          fallback_result: fallback_result,
          unknown_result: unknown_result,
          unknown_status_before_recovery: unknown_status_before_recovery,
          recovery: recovery,
          analytics: service.queries.analytics
        }.freeze
      end

      def case_configuration
        RubyRouting::Application::RoutingConfiguration.new(
          policies: [
            RubyRouting::RoutingPolicy.new(
              id: "demo-count",
              epoch: "1",
              scope: "count",
              measure: :count,
              targets: { "A" => 1, "B" => 1 },
              recovery: RubyRouting::RecoveryPolicy.new(initial_delay_seconds: 0)
            ),
            RubyRouting::RoutingPolicy.new(
              id: "demo-unknown",
              epoch: "1",
              scope: "unknown",
              measure: :count,
              targets: { "A" => 1 },
              recovery: RubyRouting::RecoveryPolicy.new(initial_delay_seconds: 0)
            ),
            RubyRouting::RoutingPolicy.new(
              id: "demo-volume",
              epoch: "1",
              scope: "volume",
              measure: :volume,
              currency: "RUB",
              targets: { "A" => 1, "B" => 1 }
            )
          ],
          provider_opportunities: %w[A B].map do |provider_id|
            RubyRouting::ProviderOpportunity.new(
              provider_id: provider_id,
              capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
            )
          end
        )
      end

      def case_providers
        {
          "A" => RubyRouting::Demo::ScriptedProvider.new(
            provider_id: "A",
            capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
            outcomes: [
              RubyRouting::NormalizedOutcome.safe_route_failure,
              RubyRouting::NormalizedOutcome.unknown,
              RubyRouting::NormalizedOutcome.success(attribution: :provider)
            ]
          ),
          "B" => RubyRouting::Demo::ScriptedProvider.new(
            provider_id: "B",
            outcomes: [RubyRouting::NormalizedOutcome.success(attribution: :provider)]
          )
        }.freeze
      end

      def strategy_providers
        {
          "A" => RubyRouting::Demo::ScriptedProvider.new(
            provider_id: "A",
            capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true),
            outcomes: Array.new(4) { RubyRouting::NormalizedOutcome.success(attribution: :provider) }
          ),
          "B" => RubyRouting::Demo::ScriptedProvider.new(
            provider_id: "B",
            outcomes: Array.new(4) { RubyRouting::NormalizedOutcome.success(attribution: :provider) }
          )
        }.freeze
      end

      def provider_calls_for(providers)
        providers.keys.sort.to_h do |provider_id|
          [provider_id, providers.fetch(provider_id).calls]
        end.freeze
      end

      def case_submit(service, id:, scope:, amount_minor:)
        service.submit(
          intent: RubyRouting::PayoutIntent.new(
            id: id,
            money: RubyRouting::Money.new(amount_minor, "RUB")
          ),
          scope: scope
        )
      end

      def strategy_report(analytics, policy_id, amounts)
        policy = analytics.primary_target_measure_by_dimension.keys.find { |dimension| dimension.policy_id == policy_id }
        raise ArgumentError, "demo analytics missing policy #{policy_id}" unless policy

        {
          policy_id: policy_id,
          runtime: :fresh_independent,
          measure: policy.measure,
          currency: policy.currency,
          input_amounts_minor: amounts,
          target: dimension_values(analytics.primary_target_measure_by_dimension, policy_id),
          primary_actual: dimension_values(analytics.primary_assignment_measure_by_dimension, policy_id)
        }.freeze
      end

      def dimension_values(entries, policy_id)
        entries.each_with_object({}) do |(dimension, value), values|
          values[dimension.provider_id] = value if dimension.policy_id == policy_id
        end.freeze
      end

      def payout_report(snapshot, status_before_recovery: nil)
        values = {
          amount_minor: snapshot.intent.money.amount_minor,
          currency: snapshot.intent.money.currency,
          status: snapshot.status,
          primary_provider_id: snapshot.primary_provider_id,
          settlement_provider_id: snapshot.settlement_provider_id,
          attempts: snapshot.attempts.map do |attempt|
            {
              provider_id: attempt.provider_id,
              role: attempt.role,
              operation_id: attempt.operation_id,
              attempt_id: attempt.attempt_id,
              phase: attempt.phase,
              outcome: attempt.outcome&.status
            }.freeze
          end.freeze
        }
        values[:status_before_recovery] = status_before_recovery unless status_before_recovery.nil?
        values.freeze
      end

      def recovery_report(pass)
        {
          limit: pass.limit,
          processed_count: pass.processed_count,
          error_count: pass.error_count,
          items: pass.items.map do |item|
            work_item = item.work_item
            {
              payout_id: work_item.payout_id,
              requested_action: work_item.action,
              provider_id: work_item.provider_id,
              operation_id: work_item.operation_id,
              attempt_id: work_item.attempt_id,
              status: item.status,
              action: item.action,
              error: item.error && item.error.class_name
            }.freeze
          end.freeze
        }.freeze
      end

      def analytics_report(analytics)
        {
          first_attempt_success_count: analytics.first_attempt_success_count,
          eventual_success_count: analytics.eventual_success_count,
          fallback_recovery_count: analytics.fallback_recovery_count,
          successful_fallback_recovery_count: analytics.successful_fallback_recovery_count,
          recovery_attempt_count: analytics.recovery_attempt_count,
          settlement_measure_by_dimension: dimension_metric_rows(analytics.settlement_measure_by_dimension)
        }.freeze
      end

      def dimension_metric_rows(entries)
        entries.map do |dimension, value|
          { dimension: dimension.to_h, value: value }.freeze
        end.sort_by do |row|
          dimension = row.fetch(:dimension)
          [dimension.fetch(:policy_id), dimension.fetch(:currency).to_s, dimension.fetch(:provider_id).to_s]
        end.freeze
      end
    end
  end
end
