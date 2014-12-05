require 'rubygems'
require 'bundler/setup'
require 'json'
require 'thread'
require 'net/http'
require 'uri'
Bundler.require
Kernel.load 'config.rb'
Kernel.load 'checks.rb'

puts 'Welcome!'

config = Configuration.for 'app'

$ghclient = Octokit::Client.new access_token: config.access_token
$ghclient.user.login

ongoing = {}

class Counter
  def initialize
    @mutex = Mutex.new
    @counter = 0
  end

  def get
    val = 0
    @mutex.synchronize do
      val = @counter
      @counter = @counter + 1
    end
    val
  end
end
$counter = Counter.new

class Callback
  attr_accessor :notes, :warnings, :errors

  def initialize
    @notes = []
    @warnings = []
    @errors = []
  end

  def note(msg)
    @notes << msg
  end
  def warning(msg)
    @warnings << msg
  end
  def error(msg)
    @errors << msg
  end
end

def fetch(uri_str, limit = 10)
  # You should choose a better exception.
  raise ArgumentError, 'too many HTTP redirects' if limit == 0

  response = Net::HTTP.get_response(URI(uri_str))

  case response
  when Net::HTTPSuccess then
    response.body
  when Net::HTTPRedirection then
    location = response['location']
    fetch(location, limit - 1)
  else
    response.value
  end
end

def format_reply(errors, warnings, notes)
  if errors.empty? and warnings.empty?
    out = "Looking good, just a few notes:\n"
  elsif errors.empty?
    out = "A few things that should be fixed:\n"
  else
    out = "Found several blocking issues:\n"
  end
  out << "\n"

  if not errors.empty?
    out << "### Errors\n"
    errors.each do |error|
      out << '* ' + error + "\n"
    end
    out << "\n"
  end

  if not warnings.empty?
    out << "### Warnings\n"
    warnings.each do |warning|
      out << '* ' + warning + "\n"
    end
    out << "\n"
  end

  if not notes.empty?
    out << "### Notes\n"
    notes.each do |note|
      out << '* ' + note + "\n"
    end
    out << "\n"
  end

  out << "Remember that these tests are done by a machine, and thus can\'t tell anything about design or code quality."
  out
end

class Worker < Workers::Worker
  def initialize(options = {})
    super(options)
    @id = $counter.get
  end

  private
  def process_event(event)
    return if event.command != :check
    callbacks = Callback.new
    $ghclient.create_status event.data[:repo], event.data[:data]['pull_request']['head']['sha'], 'pending'
    pr = $ghclient.pull_request event.data[:repo], event.data[:pr]

    if not event.data[:data]['pull_request']['mergeable']
      callbacks.error 'Github reports pull request as not mergeable. Do you need to pull in upstream changes?'
    else
      if Dir.exists? event.data[:repo] + '/' + @id.to_s
        git = Git.open event.data[:repo] + '/' + @id.to_s, log: Logger.new(STDOUT)
        git.fetch
        Dir.chdir event.data[:repo] + '/' + @id.to_s { system 'git submodule update' }
        git.reset_hard 'origin/HEAD'
        git.reset_hard event.data[:data]['pull_request']['base']['sha']
      else
        git = Git.clone event.data[:data]['repository']['clone_url'], event.data[:repo] + '/' + @id.to_s, recursive: true
      end

      patchfiledir = Dir.pwd + '/patches/' + event.data[:repo]
      patchfile = patchfiledir + '/' + event.data[:pr].to_s + '.patch'

      patch = fetch URI(event.data[:data]['pull_request']['patch_url'])
      FileUtils.mkpath patchfiledir
      File.delete patchfile if File.exists? patchfile
      open patchfile, 'wb' do |file|
        file.write patch
      end

      git.apply patchfile

      # we now have everything ready

      checks = []
      event.data[:config].repositories.each do |repo|
        if repo[:name] == event.data[:repo]
          checks = repo[:checks]
          break
        end
      end
      begin
        checks.each do |check|
          Object.const_get(check[:check]).new(check[:data]).execute callbacks, event.data[:data], pr
        end
      rescue
      end
    end

    callbacks.note 'test note'

    puts 'Checks done, posting result'
    if callbacks.errors.empty? and callbacks.warnings.empty?
      $ghclient.create_status event.data[:repo], event.data[:data]['pull_request']['head']['sha'], 'success'
    else
      $ghclient.create_status event.data[:repo], event.data[:data]['pull_request']['head']['sha'], 'failure'
    end
    if not callbacks.errors.empty? or not callbacks.warnings.empty? or not callbacks.notes.empty?
      $ghclient.post URI(event.data[:data]['pull_request']['_links']['comments']['href']).path, {:body => format_reply(callbacks.errors, callbacks.warnings, callbacks.notes)}
    end
  end
end

pool = Workers::Pool.new worker_class: Worker

puts 'Logged in as ' + $ghclient.user[:login]

post '/webhook' do
  req = JSON.parse request.body.read
  if request.env['HTTP_X_GITHUB_EVENT'] == 'pull_request'
    if req['action'] == 'opened' or req['action'] == 'synchronize'
      time = Time.now.getutc.to_i
      ongoing[req['repository']['full_name']] = [] if ongoing[req['repository']['full_name']] == nil
      ongoing[req['repository']['full_name']] << time
      pool.enqueue :check, {time: time, repo: req['repository']['full_name'], pr: req['number'], data: req, config: config}
    end
  end
end
