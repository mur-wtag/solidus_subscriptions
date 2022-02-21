# A handler for behaviour that should happen after installments are marked as
# failures
module SolidusSubscriptions
  module Dispatcher
    class AdminDispatcher < Base
      def dispatch
        cancel_order
        installments.each { |i| i.failed!(order) }
        super
      end

      def message
        "
      Something went wrong processing installments: #{installments.map(&:id).join(', ')}.
      They have been marked for reprocessing.
      Contact the Developer team to help you out.
      "
      end
    end
  end
end
