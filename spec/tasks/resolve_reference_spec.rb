# frozen_string_literal: true

require 'spec_helper'
require_relative '../../tasks/resolve_reference.rb'

describe GCloudInventory do
  def with_env(key, val)
    old_val = ENV[key]
    ENV[key] = val
    yield
  ensure
    ENV[key] = old_val
  end

  def instances
    JSON.parse(File.read(File.join(__dir__, '../fixtures/responses/instances.json')))
  end

  def credentials
    File.join(__dir__, '../fixtures/credentials/credentials.json')
  end

  let(:project) { 'bolt' }
  let(:zone)    { 'us-west1-b' }

  let(:opts) do
    { 
      project:     project,
      zone:        zone,
      credentials: credentials,
      target_mapping: {
        name: 'name',
        uri:  'networkInterfaces.0.accessConfigs.0.natIP'
      }
    }
  end

  # Prevent any HTTP requests from going through
  before :each do
    allow(subject).to receive(:request).and_return(nil)
  end

  describe '#resolve_reference' do
    before :each do
      allow(subject).to receive(:get_all_instances).and_return(instances)
    end

    it 'generates a list of targets with ip addresses' do
      allow(subject).to receive(:token).and_return({})

      targets = [
        { name: 'instance-1', uri: '35.0.0.0' },
        { name: 'instance-2', uri: '34.0.0.0' }
      ]

      expect(subject.resolve_reference(opts)).to match_array(targets)
    end
  end

  describe '#credentials' do
    it 'loads credentials from the supplied option' do
      creds = JSON.parse(File.read(credentials))
      expect(subject.credentials(opts)).to eq(creds)
    end

    it 'loads credentials from an environment variable' do
      with_env('GOOGLE_APPLICATION_CREDENTIALS', credentials) do
        creds = JSON.parse(File.read(credentials))
        opts.delete(:credentials)
        expect(subject.credentials(opts)).to eq(creds)
      end
    end

    it 'raises an error when a credentials file is missing' do
      opts.delete(:credentials)
      expect { subject.credentials(opts) }.to raise_error(TaskHelper::Error, /Missing application credentials/)
    end

    it 'raises an error when a credentials file is missing required keys' do
      allow(File).to receive(:read).and_return('{}')
      expect { subject.credentials(opts) }.to raise_error(TaskHelper::Error, /Missing required keys/)
    end

    it 'raises an error when a credentials file has the wrong project id' do
      opts[:project] = 'puppet'
      expect { subject.credentials(opts) }.to raise_error(TaskHelper::Error, /does not match project/)
    end

    it 'raises an error when a credentials file cannot be loaded' do
      opts[:credentials] = File.join(__dir__, 'fake_file')
      expect { subject.credentials(opts) }.to raise_error(TaskHelper::Error, /Unable to read/)
    end

    it 'raises an error when a credentials file cannot be parsed as JSON' do
      allow(File).to receive(:read).and_return('not json')
      expect { subject.credentials(opts) }.to raise_error(TaskHelper::Error, /Unable to parse/)
    end

    it 'raises an error when a credentials file is not a hash' do
      allow(File).to receive(:read).and_return('"data"')
      expect { subject.credentials(opts) }.to raise_error(TaskHelper::Error, /Expected credentials to be a Hash/)
    end
  end

  describe '#get_all_instances' do
    let(:token) { { 'token_type' => 'foo', 'access_token' => 'bar' } }

    it 'paginates' do
      [1, 2, 3].each do |i|
        uri = URI.parse("https://example.com/page?pageToken=#{i}")
        response = { 'items'         => %W[#{i}a #{i}b #{i}c],
                     'nextPageToken' => i + 1,
                     'selfLink'      => 'https://example.com/page' }
        allow(subject).to receive(:request).with(:Get, uri, nil, anything).and_return(response)
      end

      uri = URI.parse('https://example.com/page?pageToken=4')
      response = { 'items' => %w[4a 4b 4c] }
      allow(subject).to receive(:request).with(:Get, uri, nil, anything).and_return(response)

      results = subject.get_all_instances('https://example.com/page?pageToken=1', token)
      expect(results).to eq(%w[1a 1b 1c 2a 2b 2c 3a 3b 3c 4a 4b 4c])
    end
  end

  describe "#task" do
    it 'returns the list of targets' do
      targets = [
        { uri: '1.2.3.4', name: 'my-instance' },
        { uri: '1.2.3.5', name: 'my-other-instance' }
      ]

      allow(subject).to receive(:resolve_reference).and_return(targets)

      result = subject.task(opts)
      expect(result).to have_key(:value)
      expect(result[:value]).to eq(targets)
    end

    it 'returns an error if one is raised' do
      error = TaskHelper::Error.new('something went wrong', 'bolt.test/error')
      allow(subject).to receive(:resolve_reference).and_raise(error)
      result = subject.task({})

      expect(result).to have_key(:_error)
      expect(result[:_error]['msg']).to match(/something went wrong/)
    end
  end
end
