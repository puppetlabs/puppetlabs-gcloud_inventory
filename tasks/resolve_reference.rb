#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../ruby_task_helper/files/task_helper'
require_relative '../../ruby_plugin_helper/lib/plugin_helper'
require 'net/http'
require 'openssl'
require 'json'
require 'jwt'

class GCloudInventory < TaskHelper
  include RubyPluginHelper

  AUTH_SCOPE        = 'https://www.googleapis.com/auth/compute.readonly'
  AUTH_SKEW         = 60
  CREDENTIALS_ENV   = 'GOOGLE_APPLICATION_CREDENTIALS'
  CREDENTIALS_KEYS  = %w[client_email private_key token_uri].freeze
  GRANT_TYPE        = 'urn:ietf:params:oauth:grant-type:jwt-bearer'
  SIGNING_ALGORITHM = 'RS256'

  def resolve_reference(opts)
    # Validate the target mapping
    template = opts.delete(:target_mapping) || {}
    unless template.key?(:uri) || template.key?(:name)
      msg = "You must provide a 'name' or 'uri' in 'target_mapping' for the Google Cloud inventory plugin"
      raise TaskHelper::Error.new(msg, 'bolt.plugin/validation-error')
    end

    # Retrieve credentials and access token for the API requests
    creds = credentials(opts)
    token = token(creds)
    url   = "https://compute.googleapis.com/compute/v1/projects/#{opts[:project]}/zones/#{opts[:zone]}/instances"

    # Build a list of compute engine instances, making multiple API requests if needed
    instances = get_all_instances(url, token)

    instances.map do |instance|
      apply_mapping(template, instance)
    end
  end

  # Hash of required credentials for authorizing with Google authentication server
  # The file path to the credentials file is loaded from either the plugin config
  # or from an evironment variable
  def credentials(opts)
    # Ensure a credentials file was specified
    unless opts[:credentials] || ENV[CREDENTIALS_ENV]
      msg = "Missing application credentials. Specify the path to the application credentials file "\
            "under the 'credentials' configuration option or as the 'GOOGLE_APPLICATION_CREDENTIALS' "\
            "environment variable."
      raise TaskHelper::Error.new(msg, 'bolt.plugin/validation-error')
    end

    path        = File.expand_path(opts[:credentials] || ENV[CREDENTIALS_ENV], opts[:_boltdir])
    credentials = JSON.parse(File.read(path))

    # Ensure the credentials are a hash
    unless credentials.is_a? Hash
      msg = "Expected credentials to be a Hash, received #{credentials.class}"
      raise TaskHelper::Error.new(msg, 'bolt.plugin/validation-error')
    end

    # Ensure the credentials have the required keys
    if (keys = CREDENTIALS_KEYS - credentials.keys).any?
      msg = "Missing required keys in credentials file: #{keys.join(', ')}"
      raise TaskHelper::Error.new(msg, 'bolt.plugin/validation-error')
    end

    credentials
  rescue Errno::ENOENT => e
    msg = "Unable to read credentials file #{path}: #{e.message}"
    raise TaskHelper::Error.new(msg, 'bolt.plugin/file-error')
  rescue JSON::ParserError => e
    msg = "Unable to parse credentials file #{path} as JSON: #{e.message}"
    raise TaskHelper::Error.new(msg, 'bolt.plugin/file-error')
  end

  # Requests an access token from the Google authentication server
  def token(creds)
    data = {
      'grant_type' => GRANT_TYPE,
      'assertion'  => jwt(creds)
    }

    uri = URI.parse(creds['token_uri'])

    request(:Post, uri, data)
  end

  # Create a JSON web token to authenticate with the Google authentication server
  def jwt(creds)
    time = Time.new

    assertion = {
      'iss'   => creds['client_email'],       # client's email address, typically a service account
      'scope' => AUTH_SCOPE,                  # request read only access to the compute engine API
      'aud'   => creds['token_uri'],          # endpoint to request the access token
      'exp'   => (time + AUTH_SKEW).to_i,     # token expires after 1 hour
      'iat'   => (time - AUTH_SKEW).to_i      # the time this assertion was created
    }

    signing_key = OpenSSL::PKey::RSA.new(creds['private_key'])

    # Encode the JSON web token
    # Google's authentication server relies on the RSA SHA-256 algorithm
    JWT.encode(assertion, signing_key, SIGNING_ALGORITHM)
  end

  # Builds a list of instances, making multiple API requests as needed
  def get_all_instances(url, token)
    header = {
      'Authorization' => "#{token['token_type']} #{token['access_token']}"
    }

    instances = []

    while url
      debug("Making request to #{url}")

      # Update the URI and make the next request
      uri = URI.parse(url)
      result = request(:Get, uri, nil, header)

      # Add the VMs to the list of instances
      instances.concat(result['items'])

      # Continue making requests until there is no longer a nextLink
      url = result['nextPageToken'] ? "#{result['selfLink']}?pageToken=#{result['nextPageToken']}" : nil
    end

    instances
  end

  # Handles the HTTP request and parses the response
  def request(verb, uri, data, header = {})
    # Create the client
    client = Net::HTTP.new(uri.host, uri.port)

    # Google Cloud REST API always uses SSL
    client.use_ssl = true
    client.verify_mode = OpenSSL::SSL::VERIFY_PEER

    # Build the request
    request = Net::HTTP.const_get(verb).new(uri.request_uri, header)

    # Build the query if there's data to send
    query = URI.encode_www_form(data) if data

    # Send the request
    begin
      response = client.request(request, query)
    rescue StandardError => e
      raise TaskHelper::Error.new(
        "Failed to connect to #{uri}: #{e.message}",
        'bolt.plugin/gcloud-http-error'
      )
    end

    # Parse the response, creating an Error object if the response
    # is not 'OK'
    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    else
      result = JSON.parse(response.body)
      err    = result['error']['message']
      msg    = String.new("#{response.code} \"#{response.msg}\"")
      msg   += ": #{err}" if err
      raise TaskHelper::Error.new(msg, 'bolt.plugin/gcloud-http-error')
    end
  end

  def task(opts)
    targets = resolve_reference(opts)
    { value: targets }
  rescue TaskHelper::Error => e
    # ruby_task_helper doesn't print errors under the _error key, so we have to
    # handle that ourselves
    { _error: e.to_h }
  end
end

if $PROGRAM_NAME == __FILE__
  GCloudInventory.run
end
