const AWS = require("aws-sdk");
const docClient = new AWS.DynamoDB.DocumentClient();

module.exports.handler = async (event) => {
	const method = event.requestContext.http.method;
	const body = event.body;
	const userid = event.pathParameters.userid;

	if (method === "GET") {
		const user = await docClient.get({
			TableName: process.env.TABLE,
			Key: {userid},
		}).promise();

		return user.Item;
	}else if (method === "PUT") {
		const user = JSON.parse(body);

		await docClient.put({
			TableName: process.env.TABLE,
			Item: {
				...user,
				userid,
			},
		}).promise();

		return {status: "OK"};
	}else if (method === "DELETE") {
		await docClient.delete({
			TableName: process.env.TABLE,
			Key: {userid},
		}).promise();

		return {status: "OK"};
	}else if (method === "OPTIONS") {
		return {
			statusCode: 200,
		};
	}
};

