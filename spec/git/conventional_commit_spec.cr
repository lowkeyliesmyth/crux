require "../spec_helper"

private alias CC = Crux::Git::ConventionalCommit

describe Crux::Git::ConventionalCommit do
  describe "#header_line" do
    it "renders type and subject" do
      CC.new(type: "feat", subject: "add thing").header_line.should eq("feat: add thing")
    end

    it "includes the scope when present" do
      CC.new(type: "fix", subject: "patch", scope: "api").header_line.should eq("fix(api): patch")
    end

    it "prefixes the ticket before the subject" do
      commit = CC.new(type: "feat", subject: "add", scope: "api", ticket: "JIRA-12")
      commit.header_line.should eq("feat(api): JIRA-12 add")
    end

    it "marks breaking changes with a bang" do
      CC.new(type: "feat", subject: "drop v1", breaking: true).header_line.should eq("feat!: drop v1")
    end

    it "ignores an empty scope" do
      CC.new(type: "feat", subject: "x", scope: "").header_line.should eq("feat: x")
    end
  end

  describe "#render" do
    it "appends the body after a blank line" do
      commit = CC.new(type: "feat", subject: "add", body: "Some detail.")
      commit.render.should eq("feat: add\n\nSome detail.")
    end

    it "appends a BREAKING CHANGE footer with its description" do
      commit = CC.new(type: "feat", subject: "drop v1", breaking: true, breaking_description: "v1 endpoints removed")
      commit.render.should eq("feat!: drop v1\n\nBREAKING CHANGE: v1 endpoints removed")
    end

    it "falls back to the subject for the breaking footer when undescribed" do
      commit = CC.new(type: "feat", subject: "drop v1", breaking: true)
      commit.render.should eq("feat!: drop v1\n\nBREAKING CHANGE: drop v1")
    end

    it "combines body and breaking footer" do
      commit = CC.new(type: "feat", subject: "x", body: "why", breaking: true, breaking_description: "boom")
      commit.render.should eq("feat!: x\n\nwhy\n\nBREAKING CHANGE: boom")
    end
  end

  describe "#validate!" do
    it "passes for a well-formed commit" do
      CC.new(type: "feat", subject: "ok").validate!
    end

    it "rejects an empty type" do
      expect_raises(Crux::Git::CommitError, /type is required/) do
        CC.new(type: "  ", subject: "ok").validate!
      end
    end

    it "rejects a type outside the allowed set" do
      expect_raises(Crux::Git::CommitError, /unknown commit type/) do
        CC.new(type: "wip", subject: "ok").validate!(["feat", "fix"])
      end
    end

    it "rejects an empty subject" do
      expect_raises(Crux::Git::CommitError, /subject is required/) do
        CC.new(type: "feat", subject: "").validate!
      end
    end

    it "rejects an over-long header line" do
      expect_raises(Crux::Git::CommitError, /exceeds/) do
        CC.new(type: "feat", subject: "x" * 80).validate!
      end
    end

    it "accepts any type when allowed_types is empty" do
      CC.new(type: "anything", subject: "ok").validate!([] of String)
    end
  end
end
