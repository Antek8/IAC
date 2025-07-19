Phase 1: Background File Upload (Before the prompt is sent)
This phase begins the moment the user selects a file in the UI.

Initiate Upload Session: The user's browser (JavaScript running on the MonolithASG) makes a preliminary API call to the AgenticASG to signal the start of an upload.

Generate Upload ID & Pre-Signed URL: The AgenticASG acts as the orchestrator.

It generates a unique upload_id (e.g., a UUID). This ID will represent this specific file for its entire lifecycle.

It generates a secure S3 Pre-Signed URL for the upload. Critically, it embeds a requirement in the URL's policy that the uploaded file must be tagged with the upload_id as metadata (e.g., x-amz-meta-upload-id: <the-generated-uuid>).

It immediately returns the upload_id and the pre-signed URL to the browser.

Direct Upload & Asynchronous Processing:

The user's browser uses the pre-signed URL to upload the file directly to the S3_PriorityUploads bucket. This is fast and offloads the data transfer from your servers.

The moment the upload completes, the RAG pipeline you designed (S3 Event -> SQS -> ChunkLambda -> S3 RAG Bucket -> EmbedAndIndexLambda) kicks off automatically in the background.

Crucially, the upload_id is passed along at every step: it's read from the initial S3 metadata, added to each chunk, and finally stored in the payload of every vector in Qdrant.

At this point, the file is already being processed, and the user hasn't even clicked "send" on their prompt yet.

---------------------------------------------------------

Phase 2: Prompt Submission and Contextual Retrieval
This phase occurs when the user finishes typing and submits their prompt.

Submit Prompt with Upload ID: The browser makes the main API call to the AgenticASG. This time, the payload contains two key pieces of information:

The user's prompt text.

The upload_id that it received and stored during Phase 1.

Filtered Qdrant Query: The AgenticASG now has everything it needs to connect the prompt to the pre-processed file.

It initiates a search query against Qdrant.

The query includes the user's prompt to find semantically relevant vectors.

Most importantly, it adds a metadata filter to the query. The filter instructs Qdrant: "Only search against vectors where the payload contains metadata.upload_id == <the-upload-id-from-the-api-call>."

Contextual Response: Qdrant executes the filtered search, guaranteeing that the results are restricted only to the chunks from the specific file the user uploaded moments before. The AgenticASG uses these targeted results to generate a precise, context-aware answer.

This architecture correctly reflects a modern, responsive user experience. It intelligently decouples the slow I/O operations from the user's interaction, using a stateful ID to seamlessly stitch the two asynchronous processes back together at the end.






