require "date"
require "yaml"

module Theoj
  # Fill gaps in a paper's front matter from the project's myst.yml.
  #
  # A NeuroLibre submission declares its title, authors, and affiliations in
  # myst.yml for the living preprint, so paper.md need not repeat them. The
  # deposit path still wants them in the shape paper.md front matter uses:
  # affiliations numbered by index, and each author's affiliations as a
  # comma-joined string of those indices.
  #
  # This is a port of inara's data/filters/myst-frontmatter.lua, which is the
  # canonical statement of the mapping; full-stack-server's
  # api/myst_frontmatter.py mirrors the same rules on the Python side. Keep the
  # three in step -- an author whose affiliations resolve differently depending
  # on which service is looking is worse than one that fails outright.
  #
  # The fallback is best-effort by design: a missing, unreadable, or malformed
  # myst.yml leaves the metadata exactly as it was. It must never itself be the
  # reason a deposit fails.
  module MystFrontmatter

    MYST_FILE = "myst.yml".freeze

    # Parts of a myst.yml affiliation, joined into one name string. Department
    # precedes institution to match the convention in existing NeuroLibre front
    # matter.
    NAME_PARTS = %w[
      department institution address city region postal_code country
    ].freeze

    # MyST accepts these aliases for two of the parts.
    ALIASES = { "institution" => "name", "region" => "state" }.freeze

    # Keys that fill individually, unlike authors and affiliations.
    SCALAR_KEYS = %w[title date tags bibliography].freeze

    class << self

      # Returns the paper's metadata with any gap filled from myst.yml.
      #
      # front_matter - the already-parsed paper.md front matter, or nil for a
      #                paper that has none.
      # myst_text    - the raw contents of myst.yml, or nil. Parsed here rather
      #                than in the caller so a malformed file is tolerated in
      #                one place.
      def merge(front_matter, myst_text)
        metadata = front_matter.is_a?(Hash) ? front_matter.dup : {}
        return metadata if myst_text.to_s.strip.empty?

        fallback = project_metadata(parse_project(myst_text))

        # Authors and affiliations are filled as a pair. An affiliation index
        # only means something relative to the list that defines it, so mixing
        # front matter authors with myst.yml affiliations would silently attach
        # authors to the wrong institutions.
        if blank?(metadata["authors"]) || blank?(metadata["affiliations"])
          unless blank?(fallback["authors"])
            unless blank?(metadata["authors"])
              warn "[neurolibre] #{MYST_FILE}: the paper names authors but no " \
                   "affiliations, so its author list is replaced by the one in " \
                   "#{MYST_FILE} rather than merged -- an affiliation index only " \
                   "means something relative to the list that defines it."
            end
            metadata["authors"] = fallback["authors"]
            metadata["affiliations"] = fallback["affiliations"] || []
          end
        end

        SCALAR_KEYS.each do |key|
          metadata[key] = fallback[key] if blank?(metadata[key]) && fallback.key?(key)
        end

        metadata
      end

      # Returns paper metadata derived from a myst.yml `project` mapping,
      # holding only the keys the project actually defines so the caller can
      # treat it as a set of defaults. Junk input yields an empty hash.
      def project_metadata(project)
        return {} unless project.is_a?(Hash)

        metadata = {}
        metadata["title"] = project["title"] unless blank?(project["title"])
        unless blank?(project["date"])
          # `date: 2024-01-15` -- unquoted ISO, the MyST-canonical form --
          # parses to a Date. This value ends up in a deposit payload, and
          # nothing downstream reads it structurally, so the string form is the
          # right shape.
          date = project["date"]
          metadata["date"] = date.is_a?(String) ? date : date.to_s
        end
        metadata["tags"] = project["keywords"] unless blank?(project["keywords"])
        metadata["bibliography"] = project["bibliography"] unless blank?(project["bibliography"])

        affiliations, index_of = build_affiliations(project)
        authors = build_authors(project, affiliations, index_of)

        metadata["authors"] = authors unless authors.empty?
        metadata["affiliations"] = affiliations unless affiliations.empty?
        metadata
      end

      # The contents of the nearest myst.yml at or above the paper, or nil.
      #
      # paper_path  - path to the paper (paper.md, paper.tex ...).
      # search_root - the directory the walk may climb to, normally the root of
      #               a cloned repository. When nil the walk stops at the first
      #               directory holding a .git, which is the repository root for
      #               a plain checkout; failing that, at the paper's own
      #               directory. myst.yml sits at the project root while the
      #               paper is often nested (content/paper.md), so the walk has
      #               to happen -- but it must never wander out of the tree the
      #               caller meant.
      def config_text(paper_path, search_root: nil)
        path = config_path(paper_path, search_root)
        path.nil? ? nil : File.read(path)
      end

      private

      def config_path(paper_path, search_root)
        return nil if paper_path.to_s.strip.empty?

        directory = File.expand_path(File.dirname(paper_path))
        root = search_root.nil? ? nil : File.expand_path(search_root)

        loop do
          candidate = File.join(directory, MYST_FILE)
          return candidate if File.file?(candidate)

          break if root.nil? && File.directory?(File.join(directory, ".git"))
          break if !root.nil? && (directory == root || !directory.start_with?(root))

          parent = File.dirname(directory)
          break if parent == directory

          directory = parent
        end

        nil
      end

      def parse_project(myst_text)
        data = YAML.safe_load(myst_text, permitted_classes: [Date, Time], aliases: true)
        data.is_a?(Hash) ? data["project"] : nil
      rescue Psych::Exception, ArgumentError => error
        warn "[neurolibre] could not parse #{MYST_FILE}: #{error.message}"
        nil
      end

      # Builds the indexed affiliation list and an id => index map.
      def build_affiliations(project)
        affiliations = []
        index_of = {}

        as_list(project["affiliations"]).each do |source|
          index = (affiliations.length + 1).to_s
          if source.is_a?(Hash)
            affiliations << { "index" => index, "name" => affiliation_name(source) }
            index_of[source["id"].to_s] = index unless source["id"].nil?
          else
            # MyST's validator accepts a bare string where an affiliation
            # mapping is expected. It becomes an affiliation named after that
            # string, with no id, and it still consumes its index position --
            # the Lua filter and the Python port apply the same rule, so all
            # three agree on every author's index.
            affiliations << { "index" => index, "name" => source.to_s.strip }
          end
        end

        [affiliations, index_of]
      end

      # Builds the author list, resolving affiliation ids to indices. Appends to
      # affiliations for any token matching no declared id: MyST permits ad-hoc
      # affiliations, and inventing an entry beats dropping the author's.
      def build_authors(project, affiliations, index_of)
        as_list(project["authors"]).map do |source|
          # Same MyST rule for authors: `authors: [Ada Lovelace]` is valid. A
          # bare string becomes a named author with no affiliations.
          next { "name" => source.to_s.strip } unless source.is_a?(Hash)

          author = { "name" => source["name"] }
          { "email" => "email",
            "orcid" => "orcid",
            "corresponding" => "corresponding",
            "equal-contrib" => "equal_contributor" }.each do |target, key|
            author[target] = source[key] unless source[key].nil?
          end

          indices = affiliation_tokens(source["affiliations"] || source["affiliation"]).map do |token|
            index = index_of[token]
            if index.nil?
              index = (affiliations.length + 1).to_s
              affiliations << { "index" => index, "name" => token }
              index_of[token] = index
            end
            index
          end
          author["affiliation"] = indices.join(",") unless indices.empty?

          author
        end
      end

      # Joins an affiliation's parts into a single display string.
      def affiliation_name(affiliation)
        NAME_PARTS.map { |key|
          value = affiliation[key]
          value = affiliation[ALIASES[key]] if blank?(value) && ALIASES.key?(key)
          blank?(value) ? nil : value.to_s.strip
        }.compact.join(", ")
      end

      # Normalises an author's `affiliations` value to a list of tokens. MyST
      # accepts a list, a single id, or several ids in one ';'-separated string.
      def affiliation_tokens(value)
        return [] if blank?(value)
        return value.map { |entry| entry.to_s.strip }.reject(&:empty?) if value.is_a?(Array)

        value.to_s.split(";").map(&:strip).reject(&:empty?)
      end

      # Normalises a myst.yml sequence to an Array. `affiliations: harvard` is
      # legal MyST; without this, iterating the string would walk its
      # characters.
      def as_list(value)
        return [] if value.nil?
        return value if value.is_a?(Array)

        [value]
      end

      # Is a value absent, or present but carrying nothing?
      #
      # A front matter of `title:` parses to nil, not to a missing key, and
      # "", [] and {} say the same thing. All of them must count as absent or a
      # key that was merely typed out defeats the fallback.
      def blank?(value)
        return true if value.nil?
        return value.strip.empty? if value.is_a?(String)
        return value.empty? if value.respond_to?(:empty?)

        false
      end
    end
  end
end
