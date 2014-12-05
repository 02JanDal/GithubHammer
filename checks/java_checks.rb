class GradleCheck < AbstractCheck
  def execute(callbacks, data, pr)
    output = `gradle --daemon #{@data[:tasks].join(' ')}`
    if not $?.success?
      gist = github.create_gist {
        description: 'Gradle build output',
        public: true,
        files: {
          'output.txt': {
            "content": output
          }
        }
      }
      callbacks.error 'Gradle build error: ' + Gitio.shorten(gist['url'])
    end
  end
end
