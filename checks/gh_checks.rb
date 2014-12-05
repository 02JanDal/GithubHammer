class MaxOneCommit < AbstractCheck
  def execute(callbacks, data, pr)
    if github.pull_request_commits(data['repository']['full_name'], data['number']).length > 1
      callbacks.error 'To many commits. Please squash them into one.'
    end
  end
end

class DescriptionSize < AbstractCheck
  def execute(callbacks, data, pr)
    body = github.pull_request(data['repository']['full_name'], data['number'])['body']
    if body.empty?
      callbacks.warning 'You should provide a description of what your PR does.'
    elsif body.size < @data[:minsize]
      callbacks.note 'The description of the PR is very short. Please consider extending it to better describe the changes your PR does.'
    end
  end
end
