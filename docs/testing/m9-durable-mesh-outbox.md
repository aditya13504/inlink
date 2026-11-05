# M9 Test Matrix

| Scenario | Expected result |
|---|---|
| Outbound message created | Local SQLCipher conversation record written before transport |
| App stops before route write | Startup reconstructs route from the encrypted envelope |
| Route already restored by durable mesh queue | Existing route is tolerated; receipt expectation is rebuilt |
| Incoming authenticated text | Conversation record persisted before receipt generation |
| Incoming persistence failure | No recipient receipt is sent |
| Duplicate inbound message ID/contact | Store reports existing record; no duplicate history row |
| Receipt from wrong contact | Rejected and message remains pending |
| Receipt for expired or already delivered message | Rejected |
| Valid signed receipt | Outgoing conversation status becomes delivered |
| History limit reached with pending outgoing rows | New insert fails safely instead of deleting pending rows |
