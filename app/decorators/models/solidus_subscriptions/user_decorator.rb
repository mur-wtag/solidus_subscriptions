# Spree::Users maintain a list of the subscriptions associated with them
module SolidusSubscriptions
  module UserDecorator
    def self.prepended(base)
      base.has_many(
        :subscriptions,
        class_name: 'SolidusSubscriptions::Subscription',
        foreign_key: 'user_id'
      )

      base.accepts_nested_attributes_for :subscriptions
      base.after_save(:mark_dependent_subscriptions_canceled, if: -> { saved_change_to_deleted_at? && deleted_at.present? })
    end

    private

    def mark_dependent_subscriptions_canceled
      SolidusSubscriptions::Subscription.where(user_id: id).update_all(state: 'canceled')
    end

    ::Spree.user_class.prepend(self)
  end
end
