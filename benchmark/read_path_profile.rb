# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby_routing"

module RubyRouting
  module Benchmarking
    module ReadPathProfile
      SAMPLE_SIZES = [1_000, 5_000, 12_500].freeze
      REPEATS = 7

      class BenchmarkClock
        def initialize(start_time: Time.utc(2026, 1, 1), monotonic_origin: 0)
          @time = start_time.utc.freeze
          @monotonic = monotonic_origin
        end

        def now
          @time
        end

        def monotonic
          @monotonic
        end

        def monotonic_reference_for(wall_time)
          @monotonic + Rational(wall_time.utc.to_r - @time.to_r)
        end
      end

      class SuccessProvider
        def initiate(request)
          RubyRouting::ProviderObservation.new(
            observation_id: "read-profile:#{request.operation_id}",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end

        def resolve(_request)
          raise NotImplementedError, "read profile only exercises immediate initiation"
        end
      end

      module_function

      def run(payout_count:, repeats: REPEATS)
        validate_integer!(payout_count, "payout_count")
        validate_integer!(repeats, "repeats")

        clock = BenchmarkClock.new
        policy = RubyRouting::RoutingPolicy.new(
          id: "read-profile-policy",
          epoch: "20260901",
          measure: :count,
          targets: { "A" => 1, "B" => 1 }
        )
        opportunities = %w[A B].map do |provider_id|
          RubyRouting::ProviderOpportunity.new(
            provider_id: provider_id,
            capabilities: RubyRouting::ProviderCapabilities.new(status_lookup: true)
          )
        end
        coordinator = RubyRouting::State::Coordinator.new(
          clock: clock,
          opportunities: opportunities
        )
        provider = SuccessProvider.new
        service = RubyRouting::Application::Service.new(
          coordinator: coordinator,
          providers: { "A" => provider, "B" => provider },
          policy_registry: RubyRouting::PolicyRegistry.new([policy])
        )

        payout_count.times do |index|
          result = service.submit(
            intent: RubyRouting::PayoutIntent.new(
              id: "read-profile-#{index}",
              money: RubyRouting::Money.new(100, "RUB")
            ),
            policy: policy
          )
          unless result.status == :success
            raise "read profile payout #{index} did not settle: #{result.status}"
          end
        end

        queries = service.queries
        last_payout_id = "read-profile-#{payout_count - 1}"
        sparse_payout = RubyRouting::PayoutIntent.new(
          id: "read-profile-sparse-due",
          money: RubyRouting::Money.new(100, "RUB")
        )
        sparse_commit = coordinator.prepare_and_commit_decision(
          intent: sparse_payout,
          policy: policy
        )
        coordinator.mark_attempt_started(sparse_commit)
        coordinator.apply_observation(
          RubyRouting::ProviderObservation.new(
            observation_id: "read-profile-sparse-due-observation",
            payout_id: sparse_payout.id,
            provider_id: sparse_commit.proposal.provider_id,
            operation_id: sparse_commit.proposal.operation_id,
            attempt_id: sparse_commit.proposal.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.unknown(attribution: :provider)
          )
        )
        reads = {
          analytics: -> { queries.analytics },
          typed_analytics: -> {
            queries.analytics_query(
              metric: :settlement_measure,
              group_by: %i[provider_id currency]
            )
          },
          explanation: -> { queries.explanation(last_payout_id) },
          fact_snapshot: -> { coordinator.facts },
          due_work_empty: -> { coordinator.due_recovery_work(as_of: clock.now - 1) },
          due_work_one: -> { coordinator.due_recovery_work(as_of: clock.now) }
        }
        samples = reads.to_h do |name, operation|
          operation.call
          [name, measure(operation, repeats)]
        end

        {
          payout_count: payout_count,
          fact_count: coordinator.facts.length,
          reads: samples
        }.freeze
      end

      def measure(operation, repeats)
        durations = repeats.times.map do
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          operation.call
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        end.sort
        {
          median_seconds: durations.fetch(durations.length / 2),
          p95_seconds: durations.fetch([(durations.length * 0.95).ceil - 1, 0].max),
          samples: durations.freeze
        }.freeze
      end
      private_class_method :measure

      def validate_integer!(value, label)
        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError, "#{label} must be a positive Integer"
        end
      end
      private_class_method :validate_integer!
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "Ruby: #{RUBY_DESCRIPTION}"
  puts "YJIT: #{!!(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?)}"
  puts "Read-path profile: repeated canonical application reads; benchmark evidence, not a production-scale claim"
  puts "payouts facts operation median_s p95_s"
  RubyRouting::Benchmarking::ReadPathProfile::SAMPLE_SIZES.each do |payout_count|
    report = RubyRouting::Benchmarking::ReadPathProfile.run(payout_count: payout_count)
    report.fetch(:reads).each do |operation, timings|
      puts format(
        "%7d %5d %-16s %10.6f %10.6f",
        report.fetch(:payout_count),
        report.fetch(:fact_count),
        operation,
        timings.fetch(:median_seconds),
        timings.fetch(:p95_seconds)
      )
    end
  end
end
