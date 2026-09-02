/**
 * Cognito Verify Auth Challenge Response trigger — сверяет введённый код
 * с тем, что Create Auth Challenge положил в privateChallengeParameters.
 */

export const handler = async (event) => {
  const expected = event.request.privateChallengeParameters?.answer
  const provided = event.request.challengeAnswer

  event.response.answerCorrect = expected != null && provided === expected

  return event
}
