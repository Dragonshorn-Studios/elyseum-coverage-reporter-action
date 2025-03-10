const fs = require("fs");
const core = require("@actions/core");
const github = require("@actions/github");

const token = core.getInput("github_token");
const octokit = github.getOctokit(token);
const prNumber = github.context.payload.pull_request.number;
const resultFilePath = core.getInput("result-file-path");
const resultCommentBody = fs.readFileSync(resultFilePath, "utf8");

async function run() {
  const { data: comments } = await octokit.rest.issues.listComments({
    ...github.context.repo,
    issue_number: prNumber,
  });

  const commentName =
    core.getInput("comment-name") || "Elyseum Coverage Report";

  const botComment = comments.find((comment) =>
    comment.body.includes(commentName)
  );

  let commentBody = `${resultCommentBody}`;
  if (botComment) {
    await octokit.rest.issues.updateComment({
      ...github.context.repo,
      comment_id: botComment.id,
      body: commentBody,
    });
  } else {
    await octokit.rest.issues.createComment({
      ...github.context.repo,
      issue_number: prNumber,
      body: commentBody,
    });
  }
}

run();
