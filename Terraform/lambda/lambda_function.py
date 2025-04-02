import json
import boto3
import uuid
import jwt  # For decoding the JWT token
from boto3.dynamodb.conditions import Key
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('MoviesTable')

def lambda_handler(event, context):
    try:
        http_method = event.get("httpMethod", "")
        
        if http_method == "OPTIONS":
            return generate_response(200, {"message": "CORS preflight success"})
        
        auth_header = event.get('headers', {}).get('Authorization', '')
        if auth_header:
            token = auth_header.split(' ')[1]  
            decoded_token = jwt.decode(token, options={"verify_signature": False})  
            username = decoded_token.get('preferred_username', decoded_token.get('name', 'Unknown User'))  # Extract username

        if http_method == "POST":
            body = json.loads(event["body"])
            title = body.get("title")
            genre = body.get("genre")
            rating = body.get("rating")

            if not title or not genre or not rating:
                return generate_response(400, {"error": "Title, Genre, and Rating are required"})

            movie_id = str(uuid.uuid4())

            # Add movie with no need to store username in DynamoDB
            table.put_item(Item={
                "movieId": movie_id,
                "title": title,
                "genre": genre,
                "rating": rating,
                "username": username  # Optional if you want to display the username in movie records
            })

            return generate_response(201, {"message": "Movie added successfully", "movieId": movie_id})

        elif http_method == "GET":
            if event.get("queryStringParameters") and "movieId" in event["queryStringParameters"]:
                movie_id = event["queryStringParameters"]["movieId"]
                response = table.get_item(Key={"movieId": movie_id})
                if "Item" not in response:
                    return generate_response(404, {"error": "Movie not found"})
                return generate_response(200, response["Item"])
            else:
                response = table.scan()
                movies = response.get("Items", [])
                
                # Add username to each movie if needed
                for movie in movies:
                    movie['username'] = username  # Add username to the movie object

                return generate_response(200, {"movies": movies})

        # Handle PUT and DELETE requests here...

    except Exception as e:
        return generate_response(500, {"error": str(e)})

def generate_response(status_code, body):
    """ Helper function to generate a response with CORS headers """
    return {
        "statusCode": status_code,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT,DELETE",
            "Access-Control-Allow-Headers": "Content-Type",
        },
        "body": json.dumps(body)
    }
