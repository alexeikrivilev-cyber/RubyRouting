# frozen_string_literal: true

module RubyRouting
  module Ports
    module Provider
      def initiate(_request)
        raise NotImplementedError, "provider adapter must implement #initiate"
      end

      def resolve(_request)
        raise NotImplementedError, "provider adapter must implement #resolve"
      end
    end

    # Provider-specific webhook adapters implement this boundary. Raw
    # transport fields never enter the lifecycle reducer directly.
    module ProviderNormalizer
      def normalize(_raw:, _provider_id:)
        raise NotImplementedError, "provider normalizer must implement #normalize"
      end
    end

    # Provider adapters own bounded connect, read and request deadlines for
    # their transport client. They must convert a transport result whose
    # economic meaning is known into a ProviderTransportResult or
    # ProviderTransportError. The orchestrator only handles that explicit
    # classification contract; a raw Timeout::Error or other adapter
    # programming/contract error is not guessed as definitely_not_sent. Such a
    # failure surfaces through ProviderExecutionError with the original error
    # retained as cause while the already-committed operation stays resumable
    # through its persisted identity and phase.
    #
    # Adapter network deadlines are operational bounds, not the operation
    # TTL/deadline used by the recovery policy. The generic core does not
    # asynchronously terminate provider threads to enforce either contract.
  end
end
