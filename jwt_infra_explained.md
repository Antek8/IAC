The role of the Infrastructure as Code (Terraform) is to create the secure environment and provide the necessary plumbing so that your application logic can perform this task safely and correctly.

Here is a detailed breakdown of how the responsibilities are separated and how the process works.

The Role of Application Logic (The "How")
This is the code that runs inside your GeneratePresignedUrlLambda. It's what your developers write in Python, Node.js, etc.

Receive Verified Context: The Lambda function is invoked by API Gateway. Because of the Lambda Authorizer, it receives a trusted, pre-verified payload containing the user's context (e.g., tenant_id, user_id, session_id).

Fetch the Signing Secret: The Lambda's code knows the ARN of the secret where the JWT signing key is stored (this ARN is passed in as an environment variable by the IaC). It uses the AWS SDK to make a GetSecretValue call to Secrets Manager to retrieve the actual secret key.

Construct the JWT Payload: The application logic now constructs the JSON payload for the ContextToken. It combines the trusted context it received from the authorizer with a newly generated unique ID for the file itself.

JSON

{
  "tenant_id": "acme-corp-123", // From authorizer
  "user_id": "user-jane-doe-456",   // From authorizer
  "session_id": "browser-session-789xyz", // From authorizer
  "upload_id": "a1b2c3d4-e5f6-7890-1234-567890abcdef", // Newly generated UUID
  "exp": 1678886400 // Expiration time
}
Sign the Token: Using a standard JWT library (like PyJWT in Python), the application signs this payload with the secret key it fetched from Secrets Manager. This produces the final, secure JWT string.

Return the Token: This JWT string is returned as part of the API response, alongside the pre-signed S3 URL.

The Role of Infrastructure as Code (The "Setup")
Your Terraform code does not create the JWT, but it performs the critical setup that makes the process possible and secure.

Provision the Secret: The IaC is responsible for creating the aws_secretsmanager_secret resource. It creates a secure placeholder for your JWT signing key. The actual value of the key can be set manually in the AWS console or via a secure CI/CD process, but the infrastructure for storing it is defined in code.

Grant Permission to the Secret: The IaC creates the IAM Role for the GeneratePresignedUrlLambda. Critically, it attaches a policy that grants secretsmanager:GetSecretValue permission, but only for the specific ARN of the secret created in step 1. This ensures the Lambda can't access any other secrets.

Pass the Secret's Location: The IaC passes the ARN of the secret to the Lambda function as an environment variable (e.g., JWT_SECRET_ARN). This is how the application logic knows which secret to fetch at runtime. It decouples the code from the infrastructure configuration.

How the Token is Passed (The Plumbing)
Once the application logic creates the token, it's passed through the system as metadata:

Frontend to S3: The frontend application receives the JWT and includes it as a custom metadata tag (e.g., x-amz-meta-context-token) when it uploads the file to S3 using the pre-signed URL.

S3 to SQS: When the file is created, the S3 event notification that is sent to SQS automatically includes the object's metadata. The JWT travels inside this event payload.

SQS to ChunkLambda: The ChunkLambda receives the SQS message, parses the S3 event from the message body, and extracts the JWT from the metadata section.

ChunkLambda to RAGBucket: As the ChunkLambda creates the smaller chunk files, it copies the same JWT tag onto each new chunk it saves in the S3 RAG Bucket.

RAGBucket to EmbedAndIndexLambda: The final Lambda is triggered by the creation of a chunk. It reads the chunk's metadata to get the JWT.

EmbedAndIndexLambda to Qdrant: The Lambda includes the entire JWT (or its unpacked contents) in the JSON payload of the vector it writes to Qdrant. This permanently associates the chunk's vector with its full user, tenant, and session context.