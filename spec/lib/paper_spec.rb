describe Theoj::Paper do

  describe "initialization" do
    it "should find paper and load metadata" do
      repository = "https://github.com/myorg/researchsoftware"
      branch = "paper"

      expect_any_instance_of(Theoj::Paper).to receive(:find_paper).with(nil)
      expect_any_instance_of(Theoj::Paper).to receive(:load_metadata)

      paper = Theoj::Paper.new(repository, branch)

      expect(paper.repository).to eq("https://github.com/myorg/researchsoftware")
      expect(paper.branch).to eq("paper")
    end

    it "should set empty metadata if can't find paper" do
      expect_any_instance_of(Theoj::Paper).to receive(:find_paper).and_return(nil)

      paper = Theoj::Paper.new("https://github.com/myorg/researchsoftware", "wrong-branch")

      expect(paper.paper_path).to be_nil
      expect(paper.paper_metadata).to eq({})
    end

    it "can be initialized from repo" do
      repository = "https://github.com/myorg/researchsoftware"

      expect(Theoj::Paper).to receive(:new).with(repository, "", nil)

      Theoj::Paper.from_repo(repository)
    end
  end

  describe "#paper_path" do
    before do
      expect_any_instance_of(Theoj::Paper).to receive(:load_metadata)
    end

    it "should use passed path if present" do
      expect_any_instance_of(Theoj::Paper).to_not receive(:setup_local_repo)

      paper = Theoj::Paper.new("repository", "branch", "./path/to/paper.md")

      expect(paper.paper_path).to eq("./path/to/paper.md")
    end

    it "should download repo and look for paper if no path received" do
      expect_any_instance_of(Theoj::Paper).to receive(:setup_local_repo).and_return(true)
      expect(Theoj::Paper).to receive(:find_paper_path).and_return("path-to-paper")

      paper = Theoj::Paper.new("repository", "branch")

      expect(paper.paper_path).to eq("path-to-paper")
    end
  end

  describe "#cleanup" do
    before do
      expect_any_instance_of(Theoj::Paper).to receive(:find_paper).with(nil)
      expect_any_instance_of(Theoj::Paper).to receive(:load_metadata)

      @paper = Theoj::Paper.new("repository", "branch")
      @local_path = @paper.local_path
    end

    it "should remove the repo folder if it exists" do
      expect(Dir).to receive(:exist?).with(@local_path).and_return(true)
      expect(FileUtils).to receive(:rm_rf).with(@local_path)

      @paper.cleanup
    end

    it "should do nothing if the repo folder doesn't exists" do
      expect(Dir).to receive(:exist?).with(@local_path).and_return(false)
      expect(FileUtils).to_not receive(:rm_rf)

      @paper.cleanup
    end
  end

  describe "#local_path" do
    before do
      expect_any_instance_of(Theoj::Paper).to receive(:find_paper).with(nil)
      expect_any_instance_of(Theoj::Paper).to receive(:load_metadata)
      @paper = Theoj::Paper.new("repository", "branch")
    end

    it "is located under tmp" do
      expect(@paper.local_path).to start_with("tmp")
    end

    it "is memoized" do
      expect(SecureRandom).to receive(:hex).once
      expect(@paper.local_path).to eq(@paper.local_path)
    end
  end

  describe ".find_paper_path" do
    it "should return a the paper path if present" do
      expect(Dir).to receive(:exist?).with("/repo/path/").and_return(true)
      expect(Find).to receive(:find).with("/repo/path/").and_return(["lib/papers", "./docs/paper.md", "app"])

      paper_path = Theoj::Paper.find_paper_path("/repo/path/")

      expect(paper_path).to eq("./docs/paper.md")
    end

    it "should return nil if search_path does not exists" do
      expect(Dir).to receive(:exist?).with("/repo/path/").and_return(false)

      paper_path = Theoj::Paper.find_paper_path("/repo/path/")

      expect(paper_path).to be_nil
    end

    it "should return nil if no paper file found" do
      expect(Dir).to receive(:exist?).with("/repo/path/").and_return(true)
      allow(Find).to receive(:find).with("/repo/path/").and_return(["lib/papers.pdf", "./docs", "app"])

      paper_path = Theoj::Paper.find_paper_path("/repo/path/")

      expect(paper_path).to be_nil
    end
  end

  describe "metadata" do
    before do
      @paper = Theoj::Paper.new("repository", "branch", fixture("paper_metadata.md"))
    end

    it "should have title" do
      expect(@paper.title).to eq("Nimbus: Random Forest algorithms in a genomic selection context")
    end

    it "should have tags" do
      expect(@paper.tags).to eq(["random forest", "genomics", "machine learning", "ruby", "open science"])
    end

    it "should have date" do
      expect(@paper.date).to eq("12 July 2021")
    end

    it "should have bibliography_path" do
      expect(@paper.bibliography_path).to eq("paper-bib-path.bib")
    end
  end

  describe "paper's authors" do
    before do
      @paper = Theoj::Paper.new("repository", "branch", fixture("paper_metadata.md"))
    end

    it "should be extracted from the metadata" do
      authors = @paper.authors
      expect(authors.size).to eq(2)
      expect(authors.first.name).to eq("Juanjo Bazán")
      expect(authors.first.affiliation).to eq("OpenJournals")
      expect(authors.last.name).to eq("Ellen Ripley")
      expect(authors.last.affiliation).to eq("Nostromo")
    end

    it "should include a citation author" do
      expect(@paper.citation_author).to eq("Bazán et al.")
    end
  end

  describe "authors names parsing" do
    before do
      @paper = Theoj::Paper.new("repository", "branch", fixture("parsing_names_format_metadata.md"))
    end

    it "should work with all available formats" do
      authors = @paper.authors
      expect(authors.size).to eq(3)
      expect(@paper.citation_author).to eq("Beethoven et al.")
      expect(authors.first.name).to eq("Ludwig Beethoven")
      expect(authors.first.initials).to eq("L. v.")
      expect(authors[1].name).to eq("James Bond")
      expect(authors.last.name).to eq("Ellen Ripley")
    end

  end
end

describe "a paper.md whose metadata lives in myst.yml" do
  require "tmpdir"

  MYST_YML_FOR_PAPER = <<~YAML
    version: 1
    project:
      title: Living Preprint
      authors:
        - name: Grace Hopper
          affiliations: navy
      affiliations:
        - id: navy
          institution: US Navy
  YAML

  def submission_with(paper_text)
    dir = Dir.mktmpdir
    File.write(File.join(dir, "myst.yml"), MYST_YML_FOR_PAPER)
    path = File.join(dir, "paper.md")
    File.write(path, paper_text)
    Theoj::Paper.new("repository", "branch", path)
  end

  it "falls back to myst.yml when paper.md has no front matter at all" do
    # Prose is not YAML: a line such as "Note: see below" is a mapping to Psych,
    # and a second colon on it is a syntax error. The body must never be parsed.
    paper = submission_with("# Living Preprint\n\nNote: this sentence: has two colons.\n")

    expect(paper.title).to eq("Living Preprint")
    expect(paper.authors.map(&:name)).to eq(["Grace Hopper"])
  end

  it "parses only the front matter block, not the body" do
    paper = submission_with("---\ntitle: Own Title\n---\n\nResults: mean: 3\n")

    expect(paper.title).to eq("Own Title")
    expect(paper.authors.map(&:name)).to eq(["Grace Hopper"])
  end

  it "still reports a front matter block that is malformed" do
    expect { submission_with("---\ntitle: Foo\nabc: x: y\n---\n") }.to raise_error(Psych::SyntaxError)
  end
end
