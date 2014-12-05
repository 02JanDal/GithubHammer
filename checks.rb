class AbstractCheck
  def initialize(data)
    @data = data
  end
  def execute(callbacks, data, pr)
  end
  def github
    $ghclient
  end
end

require_all 'checks'
