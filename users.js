const crypto = require("crypto");
const AWS = require("aws-sdk");
const docClient = new AWS.DynamoDB.DocumentClient();

module.exports.handler = async (event) => {
	const method = event.requestContext.http.method;
	const body = event.body;

	if (method === "GET") {
		const items = await docClient.scan({
			TableName: process.env.TABLE,
		}).promise();

		return items.Items;
	}else if (method === "POST") {
		const user = JSON.parse(body);
		const userid = crypto.randomBytes(16).toString("hex");

		await docClient.put({
			TableName: process.env.TABLE,
			Item: {
				...user,
				userid,
			},
		}).promise();
		
		return {userid};
	}else if (method === "OPTIONS") {
		return {
			statusCode: 200,
		};
	}
};

