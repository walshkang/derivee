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

// UploadToR2 uploads the compressed .zst file to Cloudflare R2
func UploadToR2(filePath string) error {
	bucket := os.Getenv("R2_BUCKET_NAME")
	endpoint := os.Getenv("R2_ENDPOINT")
	accessKey := os.Getenv("AWS_ACCESS_KEY_ID")
	secretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")
	region := os.Getenv("AWS_REGION")

	if bucket == "" || endpoint == "" || accessKey == "" || secretKey == "" {
		return fmt.Errorf("missing Cloudflare R2 environment variables")
	}

	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithRegion(region),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKey, secretKey, "")),
	)
	if err != nil {
		return fmt.Errorf("unable to load SDK config: %w", err)
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

	_, err = client.PutObject(context.TODO(), &s3.PutObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String("transit_delta.sqlite.zst"),
		Body:   file,
	})
	if err != nil {
		return fmt.Errorf("failed to upload object: %w", err)
	}

	return nil
}
