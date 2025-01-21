import boto3
import os
import json
from boto3.dynamodb.conditions import Key
from hashlib import sha256
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def shorten_url(long_url):
    try:
        short_hash = base64.urlsafe_b64encode(sha256(long_url.encode()).digest()[:6]).decode()
        table.put_item(Item={'short_url': short_hash, 'long_url': long_url})
        logger.info(f"URL shortened: {long_url} -> {short_hash}")
        return short_hash
    except Exception as e:
        logger.error(f"Error shortening URL: {e}")
        raise

def get_long_url(short_url):
    try:
        response = table.get_item(Key={'short_url': short_url})
        if 'Item' in response:
            logger.info(f"URL retrieved: {short_url} -> {response['Item']['long_url']}")
            return response['Item']['long_url']
        else:
            logger.warning(f"Short URL not found: {short_url}")
            return None
    except Exception as e:
        logger.error(f"Error retrieving URL: {e}")
        raise

def lambda_handler(event, context):
    try:
        http_method = event['httpMethod']
        if http_method == 'POST':
            long_url = json.loads(event['body']).get('long_url')
            if not long_url:
                return {'statusCode': 400, 'body': 'Invalid request: missing long_url'}
            short_url = shorten_url(long_url)
            return {'statusCode': 200, 'body': json.dumps({'short_url': short_url})}
        elif http_method == 'GET':
            short_url = event['queryStringParameters'].get('short_url')
            if not short_url:
                return {'statusCode': 400, 'body': 'Invalid request: missing short_url'}
            long_url = get_long_url(short_url)
            if long_url:
                return {'statusCode': 200, 'body': json.dumps({'long_url': long_url})}
            else:
                return {'statusCode': 404, 'body': 'Short URL not found'}
        else:
            return {'statusCode': 405, 'body': 'Method Not Allowed'}
    except Exception as e:
        logger.error(f"Unhandled error: {e}")
        return {'statusCode': 500, 'body': 'Internal Server Error'}
