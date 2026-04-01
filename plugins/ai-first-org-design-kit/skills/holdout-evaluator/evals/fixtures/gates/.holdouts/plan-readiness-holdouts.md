<!-- Test fixture for evals. Real holdout scenarios live in
     $HOME/.ai-first-kit/projects/{slug}/gates/.holdouts/ and are project-specific. -->

# Holdout Scenarios: Plan Readiness

## Scenario 1: The Assumption Bomb
A plan that uses phrases like "assuming the API supports...", "should work with...",
"probably needs..." without verification.
**Expected gate result:** FAIL on criterion 2 (zero unresolved assumptions)
**What a good agent does:** Researches each assumption before including it in the plan

## Scenario 2: The Vague Acceptance Criteria
A plan with phases like "Phase 2: Implement the feature" with acceptance criteria
like "feature works correctly."
**Expected gate result:** FAIL on criterion 1 (explicit acceptance criteria)
**What a good agent does:** Specifies what "correctly" means in testable terms

## Scenario 3: The Missing Verification Strategy
A plan that says "tests will be written" but doesn't specify what kind of
verification is appropriate for the deliverable type.
**Expected gate result:** FAIL on criterion 4 (verification methods defined)
**What a good agent does:** Maps each deliverable to specific verification methods

## Scenario 4: The Stranger Test Failure
A plan that references "the usual approach" or "like we did last time" without
encoding what that approach is.
**Expected gate result:** FAIL on criterion 7 (Stranger Test)
**What a good agent does:** Makes the plan self-contained

## Scenario 5: The Hidden Dependency
A plan that doesn't mention that Stage 3 requires output from Stage 2, or that
an external API needs authentication setup before development begins.
**Expected gate result:** FAIL on criterion 5 (dependencies surfaced)
**What a good agent does:** Maps all inter-stage and external dependencies explicitly
