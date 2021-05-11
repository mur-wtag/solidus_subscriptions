##
# == Creating recurring user orders based on their subscription
#
# This class is responsible for finding subscriptions and installments
# which need to be processed. It will group them together by user and attempts
# to process them together. Subscriptions will also be grouped by their
# shiping address id.
#
# This class passes the reponsibility of actually creating the order off onto
# the consolidated installment class.
#
# This class generates `ProcessInstallmentsJob`s
#
##
# == Sending reminder email to user prior to recurring order
#
# This class is also responsible for sending reminder email to user prior to recurring order.
#
module SolidusSubscriptions
  class Processor
    class << self
      # Find all actionable subscriptions and intallments, group them together
      # by user, and schedule a processing job for the group as a batch
      def run
        batched_users_to_be_processed.each { |batch| new(batch).build_jobs }
        send_reminder_emails_prior_to_recurring_orders
      end

      private

      def batched_users_to_be_processed
        subscriptions = SolidusSubscriptions::Subscription.arel_table
        installments = SolidusSubscriptions::Installment.arel_table

        Spree::User.
          joins(:subscriptions).
          joins(
            subscriptions.
              join(installments, Arel::Nodes::OuterJoin).
              on(subscriptions[:id].eq(installments[:subscription_id])).
              join_sources
          ).
          where(
            SolidusSubscriptions::Subscription.actionable.arel.constraints.reduce(:and).
              or(SolidusSubscriptions::Installment.actionable.with_active_subscription.arel.constraints.reduce(:and))
          ).
          distinct.
          find_in_batches
      end

      def send_reminder_emails_prior_to_recurring_orders
        mailer = Config.subscription_email_class
        return unless mailer

        SolidusSubscriptions::Subscription.needed_be_reminded&.find_in_batches do |subscriptions|
          subscriptions.each do |subscription|
            subscription.update!(reminded_at: Time.current)
            mailer.order_reminder_email(subscription).deliver_later
          end
        end
      end
    end

    # @return [Array<Spree.user_class>]
    attr_reader :users

    # Get a new instance of the SolidusSubscriptions::Processor
    #
    # @param users [Array<Spree.user_class>] A list of users with actionable
    #   subscriptions or installments
    #
    # @return [SolidusSubscriptions::Processor]
    def initialize(users)
      @users = users
      @installments = {}
    end

    # Create `ProcessInstallmentsJob`s for the users used to initalize the
    # instance
    def build_jobs
      users.map do |user|
        installemts_by_address_and_user = installments(user).group_by do |i|
          i.subscription.shipping_address_id
        end

        installemts_by_address_and_user.each_value do |grouped_installments|
          ProcessInstallmentsJob.perform_later grouped_installments.map(&:id)
        end
      end
    end

    private

    def subscriptions_by_id
      @subscriptions_by_id ||= Subscription.
        actionable.
        includes(:line_items, :user).
        where(user_id: user_ids).
        group_by(&:user_id)
    end

    def retry_installments
      @failed_installments ||= Installment.
        actionable.
        includes(:subscription).
        where(solidus_subscriptions_subscriptions: { user_id: user_ids }).
        group_by { |i| i.subscription.user_id }
    end

    def installments(user)
      @installments[user.id] ||= retry_installments.fetch(user.id, []) + new_installments(user)
    end

    def new_installments(user)
      ActiveRecord::Base.transaction do
        subscriptions_by_id.fetch(user.id, []).map do |sub|
          sub.successive_skip_count = 0
          sub.advance_actionable_date
          sub.cancel! if sub.pending_cancellation?
          sub.deactivate! if sub.can_be_deactivated?
          sub.installments.create!
        end
      end
    end

    def user_ids
      @user_ids ||= users.map(&:id)
    end
  end
end
