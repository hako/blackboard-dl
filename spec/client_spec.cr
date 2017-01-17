require "./spec_helper"
describe BlackBoard::Dl::Client do
  host = "https://blackboard.lincoln.ac.uk"
  describe "#login" do
    login = BlackBoard::Dl::LOGIN

    it "logs in" do
      WebMock.stub(:post, host + login).to_return(body: %(<?xml version="1.0" encoding="UTF-8"?>
<mobileresponse status="OK" version="94.8.0" userid="_263528_1"/>), headers: MOCK_SET_COOKIE_HEADER)

      res = BlackBoard::Dl::Client.new(host, "12345678", "abcdefghijk").login
      res.should eq "OK"
    end

    it "does not log in" do
      WebMock.stub(:post, host + login).to_return(body: %(<?xml version='1.0' encoding='UTF-8'?>
<mobileresponse status="NOT_LOGGED_IN"><![CDATA[Exception <class blackboard.plugin.beyond.bbAS.exception.BBMErrorCodeException> toString
<blackboard.plugin.beyond.bbAS.exception.BBMErrorCodeException>]]></mobileresponse>))

      res = BlackBoard::Dl::Client.new(host, "12345678", "abcdefghijk").login
      res.should eq "NOT_LOGGED_IN"
      res.should_not eq "OK"
    end
  end

  describe "#get_courses" do
    login = BlackBoard::Dl::COURSES_PATH
    it "fetches courses" do
      # Mock cookies & large response...
      BlackBoard::Dl::COOKIES["s_session_id"] = MOCK_COOKIE_HEADER["s_session_id"]
      BlackBoard::Dl::COOKIES["session_id"] = MOCK_COOKIE_HEADER["session_id"]
      BlackBoard::Dl::COOKIES["web_client_cache_guid"] = MOCK_COOKIE_HEADER["web_client_cache_guid"]

      # TODO: Find better solution than this.
      # I know hideous right? Tests pass if Crystal parses raw XML like this...
      mock_response = %(<?xml version="1.0" encoding="UTF-8"?><mobileresponse status="OK" version="12.3.4" coursesDisplayName="Sites" orgsDisplayName="Communities" defaultLocale="en_GB_tssp11v1" assessments3.0="true" pushNotifications="true"><courses><course bbid="_123456_13" name="Testing Science - 1234" courseid="abc-ts-1234" role="Sites in which you are enrolled:" isAvail="true" locale="en_GB_tssp11v1" ultraStatus="CLASSIC" lastAccessDate="2010-05-22" enrollmentdate="2016-09-17" roleIdentifier="S" durationType="CONTINUOUS" daysFromTheDateOfEnrollment="0"/><course bbid="_123456_12" name="Testing and Engineering - 1234" courseid="abc-te-1234" role="Sites in which you are enrolled:" isAvail="true" locale="en_GB_tssp11v1" ultraStatus="CLASSIC" lastAccessDate="2014-02-23" enrollmentdate="2016-10-11" roleIdentifier="S" durationType="CONTINUOUS" daysFromTheDateOfEnrollment="0"/><course bbid="_123456_11" name="Test Driven Development - 1234" courseid="abc-tdd-1234" role="Sites in which you are enrolled:" isAvail="true" locale="en_GB_tssp11v1" ultraStatus="CLASSIC" lastAccessDate="2016-05-11" enrollmentdate="2012-12-10" roleIdentifier="S" durationType="CONTINUOUS" daysFromTheDateOfEnrollment="0"/><course bbid="_123456_10" name="Test Project - 1234" courseid="ABC1234D-1234" role="Sites in which you are enrolled:" isAvail="true" locale="en_GB_tssp11v1" ultraStatus="CLASSIC" lastAccessDate="2011-01-03" enrollmentdate="2012-02-23" roleIdentifier="S" durationType="CONTINUOUS" daysFromTheDateOfEnrollment="-1"/><course bbid="_123456_9" name="Real World Testing - 5678" courseid="ABC1234E-1234" role="Sites in which you are enrolled:" isAvail="true" locale="en_GB_tssp11v1" ultraStatus="CLASSIC" lastAccessDate="2013-06-23" enrollmentdate="2014-10-07" roleIdentifier="S" durationType="CONTINUOUS" daysFromTheDateOfEnrollment="-1"/><course bbid="_123456_8" name="Test And Testing Systems - 5678" courseid="ABC1234E-1234" role="Sites in which you are enrolled:" isAvail="true" locale="en_GB_tssp11v1" ultraStatus="CLASSIC" lastAccessDate="2012-10-15" enrollmentdate="2010-04-19" roleIdentifier="S" durationType="CONTINUOUS" daysFromTheDateOfEnrollment="-1"/><course bbid="_123456_7" name="Software Testing" courseid="ts_prog" role="Sites in which you are enrolled:" isAvail="true" locale="en_GB_tssp11v1" ultraStatus="CLASSIC" lastAccessDate="2014-03-02" enrollmentdate="2014-09-08" roleIdentifier="S" durationType="CONTINUOUS" daysFromTheDateOfEnrollment="0"/></courses><orgs/><settings><setting uploadmaxfilesize="1234A"/><setting institutionalRole="year1-2AB"/></settings></mobileresponse>)
      WebMock.stub(:post, host + login).to_return(body: mock_response)
      courses = BlackBoard::Dl::Client.new(host, "12345678", "abcdefghijk").get_courses

      mock_result_courses = [
        {"id" => "_123456_13", "name" => "Testing Science - 1234"},
        {"id" => "_123456_12", "name" => "Testing and Engineering - 1234"},
        {"id" => "_123456_11", "name" => "Test Driven Development - 1234"},
      ]

      courses.each_with_index do |course, i|
        course["name"].should eq mock_result_courses[i]["name"]
      end
    end
  end
end
