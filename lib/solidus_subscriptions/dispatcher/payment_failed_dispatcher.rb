# This service class is intended to provide callback behaviour to handle
# the case where a subscription order cannot be processed because a payment
# failed
module SolidusSubscriptions
  module Dispatcher
    class PaymentFailedDispatcher < Base
      def dispatch
        cancel_order
        installments.each { |i| i.payment_failed!(order) }
        super
      end

      private

      def message
        "
      The following installments could not be processed due to payment
      authorization failure: #{installments.map(&:id).join(', ')}
        "
      end
    end
  end
end
