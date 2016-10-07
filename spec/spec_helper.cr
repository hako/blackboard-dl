require "spec"
require "webmock"
require "../src/blackboard-dl/*"

Spec.before_each &->WebMock.reset

# Mock server 'Set-Cookie' header.
MOCK_SET_COOKIE_HEADER = HTTP::Headers{
  "Set-Cookie" => [
    "session_id=B0D83004DD7715EEF9EC391732BB3174; Path=/; HttpOnly",
    "s_session_id=1DF0564EB2349C0646D87A5BAD60EE54; Path=/; Secure; HttpOnly",
    "web_client_cache_guid=fa949d03-6a76-4748-a588-1c9db6e7ce14; Path=/; Secure",
    "session_id=D119A9F836CF546530AC44C10A1DEFEB; Path=/; HttpOnly",
    "s_session_id=F210FFAE841E4EBA8ABBA93EED346F28; Path=/; Secure; HttpOnly",
    "web_client_cache_guid=26932824-a4c3-42ce-baa5-f02b3c959c31; Path=/; Secure",
  ],
}

# Mock client 'Cookie' header.
MOCK_COOKIE_HEADER = {
  "web_client_cache_guid" => "fa949d03-6a76-4748-a588-1c9db6e7ce14",
  "session_id"            => "D119A9F836CF546530AC44C10A1DEFEB",
  "s_session_id"          => "F210FFAE841E4EBA8ABBA93EED346F28; Path=/; Secure; HttpOnly",
}
