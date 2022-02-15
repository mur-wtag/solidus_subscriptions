# This service class is intended to provide callback behaviour to handle
# an installment successfully being processed
module SolidusSubscriptions
  module Dispatcher
    class SuccessDispatcher < Base
      def dispatch
        installments.each { |i| i.success!(order) }
        super
      end

      private

      def message
        "Successfully processed installments: #{installments.map(&:id).join(', ')}"
      end
    end
  end
end
