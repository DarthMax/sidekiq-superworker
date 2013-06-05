module Sidekiq
  module Superworker
    class Processor
      def complete(item, new_thread=true)
        if new_thread
          # Run this in a new thread so that its execution isn't considered to be part of the
          # completed job's execution.
          Thread.new do
            complete_item(item)
          end
        else
          complete_item(item)
        end
      end

      def error(worker, item, queue, exception)
        raise "Job has nil jid: #{item}" if item['jid'].nil?

        subjob = find_subjob_by_jid(item['jid'])
        if defined?(Sidekiq::Monitor)
          job = Sidekiq::Monitor::Job.where(queue: :superworker, jid: subjob.superjob_id).first
          if job
            result = {
              message: "#{exception.message} (thrown in #{worker.class}, JID: #{item['jid']})",
              backtrace: exception.backtrace
            }
            job.update_attributes(
              finished_at: DateTime.now,
              status: 'failed',
              result: result
            )
          end
        end
      end

      protected

      def complete_item(item)
        raise "Job has nil jid: #{item}" if item['jid'].nil?

        subjob = find_subjob_by_jid(item['jid'])
        SubjobProcessor.complete(subjob) if subjob
      end

      def find_subjob_by_jid(jid)
        # The job may complete before the Subjob record is created; in case that happens,
        # we need to sleep briefly and requery.
        tries = 3
        while !(subjob = Subjob.find_by_jid(jid)) && tries > 0
          sleep 1
          tries -= 1
        end
        subjob
      end
    end
  end
end
