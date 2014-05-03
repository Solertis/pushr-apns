module Pushr
  module Daemon
    module ApnsSupport
      class FeedbackReceiver

        FEEDBACK_TUPLE_BYTES = 38

        def initialize(configuration)
          @configuration = configuration
          @interruptible_sleep = InterruptibleSleep.new
        end

        def start
          @thread = Thread.new do
            loop do
              break if @stop
              check_for_feedback
              @interruptible_sleep.sleep @configuration.feedback_poll
            end
          end
        end

        def stop
          @stop = true
          @interruptible_sleep.interrupt_sleep
          @thread.join if @thread
        end

        def check_for_feedback
          connection = nil
          begin
            connection = ConnectionApns.new(@configuration)
            connection.connect

            while tuple = connection.read(FEEDBACK_TUPLE_BYTES)
              timestamp, device = parse_tuple(tuple)
              create_feedback(connection, timestamp, device)
            end
          rescue StandardError => e
            Pushr::Daemon.logger.error(e)
          ensure
            connection.close if connection
          end
        end

        protected

        def parse_tuple(tuple)
          failed_at, _, device = tuple.unpack('N1n1H*')
          [Time.at(failed_at).utc, device]
        end

        def create_feedback(connection, failed_at, device)
          formatted_failed_at = failed_at.strftime('%Y-%m-%d %H:%M:%S UTC')
          Pushr::Daemon.logger.info("[#{connection.name}: Delivery failed at #{formatted_failed_at} for #{device}")
          Pushr::FeedbackApns.new(app: @configuration.app, failed_at: failed_at, device: device, follow_up: 'delete').save
        end
      end
    end
  end
end
