# frozen_string_literal: true

module RubyRouting
  module Case
    class Run
      attr_reader :dataset, :state, :traffic, :attempt_ledger, :settlement_ledger,
                  :configuration, :profile, :simulator, :resolver, :decisions, :report

      def initialize(dataset:, state:, traffic:, configuration:, simulator:, resolver:, decisions:, report:,
                     profile: nil, attempt_ledger: nil, settlement_ledger: nil)
        @dataset = dataset
        @state = state
        @traffic = traffic
        @attempt_ledger = attempt_ledger
        @settlement_ledger = settlement_ledger
        @configuration = configuration
        @profile = profile
        @simulator = simulator
        @resolver = resolver
        @decisions = decisions.freeze
        @report = report
        freeze
      end
    end

    class Runner
      DEFAULT_PROVIDERS = File.expand_path("../../../data/providers.json", __dir__).freeze
      DEFAULT_HISTORY = File.expand_path("../../../data/operations_history.csv", __dir__).freeze
      DEFAULT_QUEUE = File.expand_path("../../../data/operations_queue_10.json", __dir__).freeze
      DEFAULT_PROFILE = File.expand_path("../../../data/submission_profile.json", __dir__).freeze

      def initialize(providers_path: DEFAULT_PROVIDERS, history_path: DEFAULT_HISTORY,
                     queue_path: DEFAULT_QUEUE, simulator: nil,
                     terminal_provider_id: nil, rpm_limits: {}, traffic_targets: nil,
                     resolver: nil, configuration: nil, profile_path: DEFAULT_PROFILE,
                     profile: nil)
        @providers_path = providers_path
        @history_path = history_path
        @queue_path = queue_path
        @simulator = simulator
        @terminal_provider_id = terminal_provider_id
        @rpm_limits = rpm_limits
        @traffic_targets = traffic_targets
        @configuration = configuration
        @resolver = resolver
        @profile_path = profile_path
        @profile = profile
      end

      def call
        if !@configuration.nil? && !@profile.nil?
          raise InputError, "runner accepts either profile or configuration, not both"
        end
        dataset = Input.load(
          providers_path: @providers_path,
          history_path: @history_path,
          queue_path: @queue_path
        )
        profile = if !@configuration.nil?
          nil
        elsif !@profile.nil?
          unless @profile.is_a?(SubmissionProfile)
            raise InputError, "runner profile must be SubmissionProfile"
          end
          @profile
        else
          SubmissionProfile.load(path: @profile_path, dataset: dataset)
        end
        router = Router.new(
          dataset,
          simulator: @simulator,
          terminal_provider_id: @terminal_provider_id,
          rpm_limits: @rpm_limits,
          traffic_targets: @traffic_targets,
          resolver: @resolver,
          configuration: @configuration,
          profile: profile
        )
        decisions = router.run
        Run.new(
          dataset: dataset,
          state: router.state,
          traffic: router.traffic,
          configuration: router.configuration,
          profile: router.profile,
          attempt_ledger: router.attempt_ledger,
          settlement_ledger: router.settlement_ledger,
          simulator: router.simulator,
          resolver: router.resolver,
          decisions: decisions,
          report: ReportBuilder.new(
            dataset, router.state, router.traffic, router.configuration, decisions,
            profile: router.profile, attempt_ledger: router.attempt_ledger,
            settlement_ledger: router.settlement_ledger
          ).call
        )
      end
    end
  end
end
