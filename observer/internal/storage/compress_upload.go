package storage

import (
	"context"
	"fmt"

	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/klauspost/compress/zstd"
)

// CompressSQLite reads the sqlite file, compresses it with Zstandard, and writes to output path
func CompressSQLite(inputPath, outputPath string) error {
	inData, err := os.ReadFile(inputPath)
	if err != nil {
		return fmt.Errorf("failed to read input sqlite file: %w", err)
	}

	encoder, err := zstd.NewWriter(nil, zstd.WithSingleSegment(true))
	if err != nil {
		return fmt.Errorf("failed to initialize zstd writer: %w", err)
	}
	defer encoder.Close()

	outData := encoder.EncodeAll(inData, make([]byte, 0, len(inData)))

	if err := os.WriteFile(outputPath, outData, 0644); err != nil {
		return fmt.Errorf("failed to write output zst file: %w", err)
	}

	return nil
}

// UploadToR2 uploads a file to Cloudflare R2 under the default transit_delta.sqlite.zst key
func UploadToR2(filePath string) error {
	return UploadFileToR2(filePath, "transit_delta.sqlite.zst", "application/zstd")
}

// UploadFileToR2 uploads any file to Cloudflare R2 with a specified destination key and content type
func UploadFileToR2(filePath, remoteKey, contentType string) error {
	bucket := os.Getenv("R2_BUCKET_NAME")
	endpoint := os.Getenv("R2_ENDPOINT")
	accessKey := os.Getenv("AWS_ACCESS_KEY_ID")
	secretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")
	region := os.Getenv("AWS_REGION")

	if bucket == "" || endpoint == "" || accessKey == "" || secretKey == "" {
		return fmt.Errorf("missing Cloudflare R2 environment variables (R2_BUCKET_NAME, R2_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)")
	}

	if region == "" {
		region = "auto"
	}

	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithRegion(region),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKey, secretKey, "")),
	)
	if err != nil {
		return fmt.Errorf("unable to load AWS/R2 SDK config: %w", err)
	}

	// Create S3 client pointing to R2 endpoint
	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(endpoint)
		o.UsePathStyle = true
		o.Region = region
	})

	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("unable to open file %q: %w", filePath, err)
	}
	defer file.Close()

	putInput := &s3.PutObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(remoteKey),
		Body:   file,
	}
	if contentType != "" {
		putInput.ContentType = aws.String(contentType)
	}

	_, err = client.PutObject(context.TODO(), putInput)
	if err != nil {
		return fmt.Errorf("failed to upload object %s: %w", remoteKey, err)
	}

	return nil
}

