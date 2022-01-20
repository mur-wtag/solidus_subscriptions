# This class represents a single attempt to fulfill an installment. It will
# indicate the result of that attempt.
module SolidusSubscriptions
  class InstallmentDetail < ActiveRecord::Base
    belongs_to(
      :installment,
      class_name: 'SolidusSubscriptions::Installment',
      inverse_of: :details
    )

    belongs_to(:order, class_name: 'Spree::Order', optional: true)

    validates :installment, presence: true
    alias_attribute :successful, :success

    scope :history, ->(last: nil) do
      history_scope = order(:created_at)
      last&.nonzero? ? history_scope.last(last) : history_scope
    end

    # Was the attempt at fulfilling this installment a failure?
    #
    # @return [Boolean]
    def failed?
      !success
    end
  end
end
