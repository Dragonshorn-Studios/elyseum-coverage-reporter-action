const fs = require("fs");
const { context, getOctokit } = require("@actions/github");
const token = process.env.GITHUB_TOKEN;
const octokit = getOctokit(token);
const prNumber = context.payload.pull_request.number;
const resultFilePath = process.env.RESULT_FILE_PATH;
const resultCommentBody = fs.readFileSync(resultFilePath, "utf8");

async function run() {
  const { data: comments } = await octokit.rest.issues.listComments({
    ...context.repo,
    issue_number: prNumber,
  });

  const commentName = process.env.COMMENT_NAME || "Elyseum Coverage Report";

  const botComment = comments.find((comment) =>
    comment.body.includes(commentName)
  );

  let commentBody = `# ${commentName}\n${resultCommentBody}`;
  if (botComment) {
    await octokit.rest.issues.updateComment({
      ...context.repo,
      comment_id: botComment.id,
      body: commentBody,
    });
  } else {
    await octokit.rest.issues.createComment({
      ...context.repo,
      issue_number: prNumber,
      body: commentBody,
    });
  }
}

run();
