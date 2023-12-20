# GDA Semantic Issues

In [test/GDASemanticIssues.t.sol](test/GDASemanticIssues.t.sol) I make the point that the currently implemented semantics of flow distributions is flawed.

To run:
```
forge install
forge test -vv
```

Test output:
```
Running 5 tests for test/GDASemanticIssues.t.sol:GDASemanticIssuesTest
[PASS] testIssueALucky() (gas: 1314552)
Logs:
  ------ ACTIONS ------
  alice set to 9 units
  bob set to 11 units
  distributeFlow 100
  ------ RESULT -------
  totalUnits:          20
  targetFlowRate:      100
  actualFlowRate:      100
  effectiveFlowRate:   100
  adjustmentFlowRate:  0
  aliceFlowRate:       45
  bobFlowRate:         55

[PASS] testIssueAUnlucky() (gas: 1314575)
Logs:
  ------ ACTIONS ------
  alice set to 9 units
  distributeFlow 100
  bob set to 11 units
  ------ RESULT -------
  totalUnits:          20
  targetFlowRate:      100
  actualFlowRate:      99
  effectiveFlowRate:   80
  adjustmentFlowRate:  19
  aliceFlowRate:       36
  bobFlowRate:         44

[PASS] testIssueBLucky() (gas: 1314573)
Logs:
  ------ ACTIONS ------
  alice set to 10 units
  distributeFlow 100
  bob set to 15 units
  ------ RESULT -------
  totalUnits:          25
  targetFlowRate:      100
  actualFlowRate:      100
  effectiveFlowRate:   100
  adjustmentFlowRate:  0
  aliceFlowRate:       40
  bobFlowRate:         60

[PASS] testIssueBUnlucky() (gas: 1496977)
Logs:
  ------ ACTIONS ------
  alice set to 10 units
  distributeFlow 100
  bob set to 5 units
  bob set to 15 units
  ------ RESULT -------
  totalUnits:          25
  targetFlowRate:      100
  actualFlowRate:      100
  effectiveFlowRate:   75
  adjustmentFlowRate:  25
  aliceFlowRate:       30
  bobFlowRate:         45

[PASS] testIssueBVeryUnlucky() (gas: 1496977)
Logs:
  ------ ACTIONS ------
  alice set to 10 units
  distributeFlow 100
  bob set to 91 units
  bob set to 15 units
  ------ RESULT -------
  totalUnits:          25
  targetFlowRate:      100
  actualFlowRate:      100
  effectiveFlowRate:   0
  adjustmentFlowRate:  100
  aliceFlowRate:       0
  bobFlowRate:         0

Test result: ok. 5 passed; 0 failed; 0 skipped; finished in 15.47ms

Ran 1 test suites: 5 tests passed, 0 failed, 0 skipped (5 total tests)
```