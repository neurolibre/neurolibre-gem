require_relative "../../lib/theoj/myst_frontmatter"

describe Theoj::MystFrontmatter do

  FRONT_MATTER = {
    "title" => "Front Matter Title",
    "authors" => [{ "name" => "Ada Lovelace", "affiliation" => "1" }],
    "affiliations" => [{ "index" => "1", "name" => "Analytical Engine Institute" }]
  }.freeze

  MYST_YML = <<~YAML
    project:
      title: Myst Title
      date: "02 February 2022"
      keywords:
        - myst keyword
      bibliography:
        - paper.bib
      authors:
        - name: Grace Hopper
          orcid: 0000-0001-0000-0000
          email: grace@example.org
          corresponding: true
          affiliations: society
      affiliations:
        - id: society
          institution: Royal Society
  YAML

  describe ".merge" do
    it "prefers the paper's own front matter" do
      merged = described_class.merge(FRONT_MATTER, MYST_YML)

      expect(merged["title"]).to eq("Front Matter Title")
      expect(merged["authors"].first["name"]).to eq("Ada Lovelace")
    end

    it "fills authors and affiliations for a paper.md that declares neither" do
      # The failing case: paper.md carries only a title, authors live in myst.yml.
      merged = described_class.merge({ "title" => "Only A Title" }, MYST_YML)

      expect(merged["title"]).to eq("Only A Title")
      expect(merged["authors"].first["name"]).to eq("Grace Hopper")
      expect(merged["affiliations"]).to eq([{ "index" => "1", "name" => "Royal Society" }])
    end

    it "fills the scalar keys individually" do
      merged = described_class.merge({ "authors" => [], "affiliations" => [] }, MYST_YML)

      expect(merged["title"]).to eq("Myst Title")
      expect(merged["date"]).to eq("02 February 2022")
      expect(merged["tags"]).to eq(["myst keyword"])
      expect(merged["bibliography"]).to eq(["paper.bib"])
    end

    it "fills authors and affiliations as a pair" do
      # An affiliation index only means something relative to the list that
      # defines it, so the two must never come from different sources.
      merged = described_class.merge({ "authors" => FRONT_MATTER["authors"] }, MYST_YML)

      expect(merged["authors"].first["name"]).to eq("Grace Hopper")
      expect(merged["affiliations"].first["name"]).to eq("Royal Society")
    end

    it "treats a key that is present but empty as absent" do
      merged = described_class.merge({ "title" => nil, "authors" => [] }, MYST_YML)

      expect(merged["title"]).to eq("Myst Title")
    end

    it "leaves the front matter alone when myst.yml names no authors" do
      merged = described_class.merge(FRONT_MATTER, "project:\n  title: Myst Title\n")

      expect(merged["authors"].first["name"]).to eq("Ada Lovelace")
    end

    it "tolerates a malformed myst.yml" do
      merged = described_class.merge(FRONT_MATTER, %(project:\n  title: "unterminated\n))

      expect(merged["authors"].first["name"]).to eq("Ada Lovelace")
    end

    it "tolerates a myst.yml with no project key, and no myst.yml at all" do
      expect(described_class.merge(FRONT_MATTER, "other: value\n")).to eq(FRONT_MATTER)
      expect(described_class.merge(FRONT_MATTER, nil)).to eq(FRONT_MATTER)
    end

    it "accepts a paper with no front matter at all" do
      expect(described_class.merge(nil, MYST_YML)["authors"].first["name"]).to eq("Grace Hopper")
    end

    it "does not mutate the caller's front matter" do
      front_matter = { "title" => "Only A Title" }
      described_class.merge(front_matter, MYST_YML)

      expect(front_matter).to eq({ "title" => "Only A Title" })
    end

    it "stringifies an unquoted ISO date" do
      # `date: 2024-01-15` parses to a Date, which has no business in a
      # deposit payload. Nothing downstream reads it structurally.
      merged = described_class.merge({}, "project:\n  date: 2024-01-15\n  authors:\n    - name: Ada\n")

      expect(merged["date"]).to eq("2024-01-15")
    end
  end

  describe ".project_metadata" do
    def project(yaml)
      YAML.safe_load(yaml)["project"]
    end

    it "maps the author fields the deposit uses" do
      author = described_class.project_metadata(project(MYST_YML))["authors"].first

      expect(author["name"]).to eq("Grace Hopper")
      expect(author["orcid"]).to eq("0000-0001-0000-0000")
      expect(author["email"]).to eq("grace@example.org")
      expect(author["corresponding"]).to eq(true)
      expect(author["affiliation"]).to eq("1")
    end

    it "maps equal_contributor to equal-contrib" do
      metadata = described_class.project_metadata(
        project("project:\n  authors:\n    - name: Ada\n      equal_contributor: true\n")
      )

      expect(metadata["authors"].first["equal-contrib"]).to eq(true)
    end

    it "composes an affiliation name from its parts, in order" do
      metadata = described_class.project_metadata(project(<<~YAML))
        project:
          authors:
            - name: Ada
          affiliations:
            - id: one
              department: Computing
              institution: Analytical Engine Institute
              city: London
              country: United Kingdom
      YAML

      expect(metadata["affiliations"].first["name"]).to eq(
        "Computing, Analytical Engine Institute, London, United Kingdom"
      )
    end

    it "honours the name and state aliases" do
      metadata = described_class.project_metadata(project(<<~YAML))
        project:
          authors:
            - name: Ada
          affiliations:
            - id: one
              name: Analytical Engine Institute
              state: Massachusetts
      YAML

      expect(metadata["affiliations"].first["name"]).to eq(
        "Analytical Engine Institute, Massachusetts"
      )
    end

    it "resolves several affiliation ids to a comma joined index string" do
      metadata = described_class.project_metadata(project(<<~YAML))
        project:
          authors:
            - name: Ada
              affiliations: one; three
          affiliations:
            - id: one
              institution: First
            - id: two
              institution: Second
            - id: three
              institution: Third
      YAML

      expect(metadata["authors"].first["affiliation"]).to eq("1,3")
    end

    it "accepts a list of affiliation ids" do
      metadata = described_class.project_metadata(project(<<~YAML))
        project:
          authors:
            - name: Ada
              affiliations:
                - one
                - two
          affiliations:
            - id: one
              institution: First
            - id: two
              institution: Second
      YAML

      expect(metadata["authors"].first["affiliation"]).to eq("1,2")
    end

    it "appends an undeclared affiliation id as a literal name" do
      # MyST permits ad-hoc affiliations. Inventing an entry beats dropping it.
      metadata = described_class.project_metadata(project(<<~YAML))
        project:
          authors:
            - name: Ada
              affiliations: Somewhere Else
      YAML

      expect(metadata["affiliations"]).to eq([{ "index" => "1", "name" => "Somewhere Else" }])
      expect(metadata["authors"].first["affiliation"]).to eq("1")
    end

    it "gives an author with no affiliations no affiliation key" do
      metadata = described_class.project_metadata(project("project:\n  authors:\n    - name: Ada\n"))

      expect(metadata["authors"].first).not_to have_key("affiliation")
    end

    it "accepts a bare string where an author or affiliation mapping is expected" do
      metadata = described_class.project_metadata(project(<<~YAML))
        project:
          authors:
            - Ada Lovelace
          affiliations:
            - Analytical Engine Institute
      YAML

      expect(metadata["authors"]).to eq([{ "name" => "Ada Lovelace" }])
      expect(metadata["affiliations"]).to eq([{ "index" => "1", "name" => "Analytical Engine Institute" }])
    end

    it "accepts a scalar authors or affiliations value" do
      metadata = described_class.project_metadata(project("project:\n  authors: Ada Lovelace\n"))

      expect(metadata["authors"]).to eq([{ "name" => "Ada Lovelace" }])
    end

    it "returns an empty hash for junk input" do
      expect(described_class.project_metadata(nil)).to eq({})
      expect(described_class.project_metadata("not a mapping")).to eq({})
    end

    it "does not map keys the deposit has no use for" do
      metadata = described_class.project_metadata(project(<<~YAML))
        project:
          doi: 10.1234/five
          license: CC-BY-4.0
          venue: Somewhere
          authors:
            - name: Ada
      YAML

      expect(metadata.keys).to eq(["authors"])
    end
  end
end

describe "a real submission whose paper.md declares no authors" do
  # Abridged from haplante/oct-t1-paper, the submission whose deposit failed
  # with "undefined method `each' for nil" in parse_affiliations. The paper's
  # front matter carries a title and nothing else; everything below is what
  # myst.yml has to supply.
  PAPER_FRONT_MATTER = {
    "title" => "Strong Coupling of Retinal Thickness and Optic Nerve Myelin in Vivo",
    "numbering" => { "heading_1" => false }
  }.freeze

  SUBMISSION_MYST_YML = <<~YAML
    version: 1
    project:
      title: 'Strong Coupling of Retinal Thickness and Optic Nerve Myelin in Vivo'
      authors:
        - name: Hugo Albert Plante
          orcid: 0009-0008-9235-0097
          email: hugo.albert-plante@etud.polymtl.ca
          affiliations: polymtl
          corresponding: true
        - name: Agah karakuzu
          orcid: 0000-0001-7283-271X
          affiliations: polymtl; mhi
          twitter: agahkarakuzu
        - name: Mathieu Boudreau
          orcid: 0000-0002-7726-4456
          affiliations: polymtl;
      affiliations:
        - id: polymtl
          department: Electrical Engineering
          institution: Polytechnique Montreal
          city: Montreal
        - id: mhi
          institution: Montreal Heart Institute
          city: Montreal
  YAML

  let(:merged) { Theoj::MystFrontmatter.merge(PAPER_FRONT_MATTER, SUBMISSION_MYST_YML) }

  it "resolves every author" do
    expect(merged["authors"].map { |a| a["name"] }).to eq(
      ["Hugo Albert Plante", "Agah karakuzu", "Mathieu Boudreau"]
    )
  end

  it "keeps the paper's own title" do
    expect(merged["title"]).to eq(PAPER_FRONT_MATTER["title"])
  end

  it "resolves a semicolon separated affiliation list" do
    expect(merged["authors"][1]["affiliation"]).to eq("1,2")
  end

  it "ignores a trailing semicolon" do
    expect(merged["authors"][2]["affiliation"]).to eq("1")
  end

  it "gives every author an affiliation index the affiliation list defines" do
    # Author#build_affiliation_string raises unless every index resolves, so an
    # index the list does not define fails the deposit just as loudly as nil did.
    defined_indices = merged["affiliations"].map { |a| a["index"].to_s }

    merged["authors"].each do |author|
      author["affiliation"].to_s.split(",").each do |index|
        expect(defined_indices).to include(index.strip)
      end
    end
  end

  it "drops the twitter handle, which no deposit field wants" do
    expect(merged["authors"][1]).not_to have_key("twitter")
  end
end

describe "#{Theoj::MystFrontmatter}.config_text" do
  require "tmpdir"
  require "fileutils"

  def build(tree)
    tree.each do |path, contents|
      full = File.join(@root, path)
      FileUtils.mkdir_p(File.dirname(full))
      contents == :dir ? FileUtils.mkdir_p(full) : File.write(full, contents)
    end
  end

  around do |example|
    Dir.mktmpdir { |dir| @root = dir; example.run }
  end

  it "reads a myst.yml beside the paper" do
    build("paper.md" => "---\n---\n", "myst.yml" => "project:\n  title: T\n")

    expect(Theoj::MystFrontmatter.config_text(File.join(@root, "paper.md")))
      .to include("title: T")
  end

  it "walks up to the project root for a nested paper" do
    # content/paper.md with myst.yml at the root is a normal MyST layout.
    build(".git" => :dir, "myst.yml" => "project:\n  title: T\n",
          "content/paper.md" => "---\n---\n")

    expect(Theoj::MystFrontmatter.config_text(File.join(@root, "content", "paper.md")))
      .to include("title: T")
  end

  it "stops at the repository root when given no search root" do
    # A myst.yml belonging to some unrelated parent directory must not be read.
    build("repo/.git" => :dir, "repo/content/paper.md" => "---\n---\n",
          "myst.yml" => "project:\n  title: Outside The Repo\n")

    expect(Theoj::MystFrontmatter.config_text(File.join(@root, "repo", "content", "paper.md")))
      .to be_nil
  end

  it "stops at an explicit search root" do
    build("clone/content/paper.md" => "---\n---\n",
          "myst.yml" => "project:\n  title: Outside The Clone\n")

    expect(Theoj::MystFrontmatter.config_text(
      File.join(@root, "clone", "content", "paper.md"), search_root: File.join(@root, "clone")
    )).to be_nil
  end

  it "prefers the closest myst.yml" do
    build(".git" => :dir, "myst.yml" => "project:\n  title: Root\n",
          "content/myst.yml" => "project:\n  title: Closest\n",
          "content/paper.md" => "---\n---\n")

    expect(Theoj::MystFrontmatter.config_text(File.join(@root, "content", "paper.md")))
      .to include("title: Closest")
  end

  it "is nil when there is no myst.yml, and for a blank path" do
    build("paper.md" => "---\n---\n")

    expect(Theoj::MystFrontmatter.config_text(File.join(@root, "paper.md"))).to be_nil
    expect(Theoj::MystFrontmatter.config_text("")).to be_nil
    expect(Theoj::MystFrontmatter.config_text(nil)).to be_nil
  end
end
