require "securerandom"

module Theoj
  class ReviewIssue
    include Theoj::GitHub

    attr_accessor :issue_id
    attr_accessor :repository
    attr_accessor :paper
    attr_accessor :local_path

    def initialize(repository, issue_id, access_token=nil)
      @issue_id = issue_id
      @repository = repository
      @github_access_token = access_token
    end

    def issue_body
      @issue_body ||= issue(repository, issue_id).body
    end

    def paper
      @paper ||= Theoj::Paper.new(target_repository, paper_branch)
    end

    def target_repository
      @target_repository ||= read_value_from_body("target-repository")
    end

    def reviewers
      @reviewers ||= read_value_from_body("reviewers-list").split(",").map{|r| r.strip} - ["Pending", "TBD"]
    end

    def editor
      @editor ||= read_value_from_body("editor")
    end

    #@NeuroLibre -- START
    # Removes @archive, uses the following instead.
    def book_exec_url
      @book_exec_url ||= read_value_from_body("book-exec-url")
    end

    def repository_archive
      @repository_archive ||= read_value_from_body("repository-archive")
    end

    def data_archive
      @data_archive ||= read_value_from_body("data-archive")
    end

    def book_archive
      @book_archive ||= read_value_from_body("book-archive")
    end

    def docker_archive
      @docker_archive ||= read_value_from_body("docker-archive")
    end
    #@NeuroLibre -- END

    def version
      @version ||= read_value_from_body("version")
    end

    def paper_branch
      @paper_branch ||= read_value_from_body("branch")
    end

    def value_for(value_name)
      read_value_from_body(value_name)
    end

    private

      def read_from_body(start_mark, end_mark)
        text = ""
        issue_body.match(/#{start_mark}(.*)#{end_mark}/im) do |m|
          text = m[1]
        end

        text = "" if ["Pending", "TBD"].include?(text.strip)
        text.strip
      end

      # Read value in issue's body between HTML comments
      def read_value_from_body(value_name)
        start_mark = "<!--#{value_name}-->"
        end_mark = "<!--end-#{value_name}-->"
        read_from_body(start_mark, end_mark)
      end
  end
end
