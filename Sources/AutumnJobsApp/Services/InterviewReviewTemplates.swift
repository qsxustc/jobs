import Foundation

struct InterviewReviewTemplate: Identifiable {
    let id: String
    let name: String
    let icon: String
    let questions: String
    let review: String
}

enum InterviewReviewTemplates {
    static let all: [InterviewReviewTemplate] = [
        InterviewReviewTemplate(
            id: "technical",
            name: "技术面复盘",
            icon: "chevron.left.forwardslash.chevron.right",
            questions: """
            1. 算法与数据结构：
            2. 计算机基础：
            3. 项目经历追问：
            4. 系统设计：
            5. 反问环节：
            """,
            review: """
            【整体表现】

            【回答较好的部分】

            【卡住或不确定的问题】

            【表达与沟通】

            【下一轮需要补充】

            【自我评分】__/10
            """
        ),
        InterviewReviewTemplate(
            id: "product",
            name: "产品面复盘",
            icon: "lightbulb.max.fill",
            questions: """
            1. 产品分析题：
            2. 用户与需求判断：
            3. 数据指标与增长：
            4. 项目经历追问：
            5. 业务理解与反问：
            """,
            review: """
            【业务理解是否准确】

            【分析框架是否完整】

            【数据和案例是否充分】

            【沟通中的不足】

            【下一轮准备重点】

            【自我评分】__/10
            """
        ),
        InterviewReviewTemplate(
            id: "hr",
            name: "HR 面复盘",
            icon: "person.text.rectangle",
            questions: """
            1. 自我介绍与求职动机：
            2. 公司和岗位意向：
            3. 优缺点与冲突经历：
            4. 薪资、地点和到岗时间：
            5. 反问环节：
            """,
            review: """
            【动机表达】

            【稳定性与岗位匹配】

            【关键信息确认】

            【仍需向 HR 询问】

            【风险点】

            【自我评分】__/10
            """
        )
    ]
}
