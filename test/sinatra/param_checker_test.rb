require 'date'

require 'test_helper'

module Sinatra

  class ParamCheckerTest < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil ParamChecker::VERSION
    end


    def setup
    end

  end
end
