# CONFIGURATION
#

module Logjam
  # Logjam.base_url = 'stats'

  # Make sure to enable matchers appropriate for the log files that will be imported.
  # The sample log file included with LogJam is in basic time bandit format.
  # It is ok to have multiple COMPLETED matchers enabled; the first to match will be used.
  RequestInfo.register_matcher Matchers::PROCESSING
  RequestInfo.register_matcher Matchers::SESSION_XING
  RequestInfo.register_matcher Matchers::COMPLETED_XING
end
